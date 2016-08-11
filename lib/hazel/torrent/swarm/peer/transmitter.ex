defmodule Hazel.Torrent.Swarm.Peer.Transmitter do
  @moduledoc false

  use GenStateMachine

  alias Hazel.PeerWire
  alias Hazel.Torrent.Swarm.Peer

  # Client API
  def start_link(session, peer_id) do
    session_id = {session, peer_id}
    GenStateMachine.start_link(__MODULE__, %{session: session_id}, name: via_name(session_id))
  end

  defp via_name(pid) when is_pid(pid), do: pid
  defp via_name(session), do: {:via, :gproc, transmitter_name(session)}
  defp transmitter_name({{local_id, info_hash}, peer_id}), do: {:n, :l, {__MODULE__, local_id, info_hash, peer_id}}

  def where_is(session) do
    case :gproc.where(transmitter_name(session)) do
      :undefined ->
        {:error, :unknown_peer_transmitter}

      pid when is_pid(pid) ->
        {:ok, pid}
    end
  end

  def handover_socket(session, connection) do
    GenStateMachine.call(via_name(session), {:connection, connection})
  end

  def append(session, job) do
    GenStateMachine.cast(via_name(session), {:job, :append, job})
  end
  def prepend(session, job) do
    GenStateMachine.cast(via_name(session), {:job, :prepend, job})
  end
  # delete_job()

  def add_tokens(session, tokens) do
    GenStateMachine.cast(via_name(session), {:set_tokens, tokens})
  end

  # Server callbacks
  defstruct [session: nil, status: Allowance.new(nil),
             job_queue: :queue.new(), current_job: nil,
             socket: nil, transport: nil]

  def init(opts) do
    session = opts[:session]
    {:ok, :awaiting_socket, %__MODULE__{session: session}}
  end

  def handle_event({:call, from}, {:connection, {transport, socket}}, :awaiting_socket, state) do
    new_state = %{state|transport: transport, socket: socket}
    {:next_state, :consume, new_state, {:reply, from, :ok}}
  end

  # altering the job queue
  def handle_event(:cast, {:job, type, jobs}, _, state) when is_list(jobs) do
    next_events =
      Enum.map(jobs, &({:next_event, :cast, {:job, type, &1}}))
    {:keep_state, state, next_events}
  end
  def handle_event(:cast, {:job, :append, job}, _, state) do
    new_state =
      unless :queue.member(job, state.job_queue) do
        %{state|job_queue: :queue.in(job, state.job_queue)}
      else
        state
      end
    {:keep_state, new_state}
  end

  def handle_event(:cast, {:job, :prepend, job}, _, state) do
    new_state =
      if :queue.member(job, state.job_queue) do
        # If the job is already in queue it should get moved to the
        # front (i.e. there will only be one of that job in the queue)
        queue = :queue.filter(fn j -> j != job end, state.job_queue)
        %{state|job_queue: :queue.in_r(job, queue)}
      else
        %{state|job_queue: :queue.in_r(job, state.job_queue)}
      end
    {:keep_state, new_state}
  end

  # transmitting data
  def handle_event(:internal, :consume, :consume, %{current_job: nil} = state) do
    case :queue.out(state.job_queue) do
      {{:value, job}, queue} ->
        encoded_job = PeerWire.encode(job)
        status = Allowance.set_remaining(state.status, byte_size(encoded_job))
        new_state = %{state|job_queue: queue, current_job: encoded_job, status: status}
        next_event = {:next_event, :internal, :consume}
        {:keep_state, new_state, next_event}

      {:empty, _} ->
        {:keep_state, state}
    end
  end
  def handle_event(:internal, :consume, :consume, %{status: {{_, 0}, _}} = state) do
    {message, status} = Allowance.get_and_reset_buffer(state.status)
    Peer.Controller.outgoing(state.session, PeerWire.decode(message))
    next_event = {:next_event, :internal, :consume}
    {:keep_state, %{state|status: status, current_job: nil}, next_event}
  end
  def handle_event(:internal, :consume, :consume, %{status: {_, 0}} = state) do
    # ran out of tokens, await more tokens ...
    {:keep_state, state}
  end
  def handle_event(:internal, :consume, :consume, %{status: status, current_job: current} = state) do
    {tokens, status} = Allowance.take_tokens(status, byte_size(current))
    <<message::binary-size(tokens), remaining::binary>> = current
    case apply(state.transport, :send, [state.socket, message]) do
      :ok ->
        {:ok, status} = Allowance.write_buffer(status, message)
        new_state = %{state|status: status, current_job: remaining}
        next_event = {:next_event, :internal, :consume}
        {:keep_state, new_state, next_event}

      {:error, reason} ->
        {:stop, reason, state}
    end
  end

  # tokens
  def handle_event(:cast, {:set_tokens, tokens}, _, %{status: status} = state) do
    new_state = %{state|status: Allowance.set_tokens(status, tokens)}
    next_event = {:next_event, :internal, :consume}
    {:keep_state, new_state, next_event}
  end
end
