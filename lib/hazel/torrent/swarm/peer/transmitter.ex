defmodule Hazel.Torrent.Swarm.Peer.Transmitter do
  @moduledoc false

  use GenStateMachine

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
    GenStateMachine.cast(via_name(session), {:append_job, job})
  end
  # prepend(pid, job)
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
  def handle_event(:cast, {:append_job, job}, _, state) do
    apply(state.transport, :send, [state.socket, Atom.to_string(job)])
    {:keep_state, %{state|job_queue: :queue.in(job, state.job_queue)}}
  end

  # transmitting data
  def handle_event(:internal, :consume, :consume, state) do
    {:keep_state, state}
  end

  # tokens
  def handle_event(:cast, {:set_tokens, tokens}, _, %{status: status} = state) do
    new_state = %{state|status: Allowance.set_tokens(status, tokens)}
    next_event = {:next_event, :internal, :consume}
    {:keep_state, new_state, next_event}
  end
end
