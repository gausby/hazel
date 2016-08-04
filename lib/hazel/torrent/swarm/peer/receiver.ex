defmodule Hazel.Torrent.Swarm.Peer.Receiver do
  @moduledoc false

  @max_tokens_at_a_time 200
  @message_timeout 60_000
  @length_timeout 60_000

  use GenStateMachine

  defstruct(
    transport: nil, socket: nil,
    status: Allowance.new(nil),
    session: nil
  )
  alias Hazel.Torrent.Swarm.Peer

  # Client API
  def start_link(session, peer_id) do
    session_ref = {session, peer_id}
    state = %__MODULE__{session: session_ref}
    GenStateMachine.start_link(__MODULE__, state, name: via_name(session_ref))
  end

  def init(state) do
    {:ok, :awaiting_socket, state}
  end

  defp via_name(pid) when is_pid(pid), do: pid
  defp via_name({session, peer_id}),
    do: {:via, :gproc, receiver_name({session, peer_id})}
  defp receiver_name({{local_id, info_hash}, peer_id}),
    do: {:n, :l, {__MODULE__, local_id, info_hash, peer_id}}

  def where_is(session) do
    case :gproc.where(receiver_name(session)) do
      :undefined ->
        {:error, :unknown_peer_receiver}

      pid when is_pid(pid) ->
        {:ok, pid}
    end
  end

  def handover_socket(session, connection) do
    GenStateMachine.cast(via_name(session), {:handover, connection})
  end

  def add_tokens(session, tokens) do
    GenStateMachine.cast(via_name(session), {:add_tokens, tokens})
  end

  # Server callbacks
  def handle_event(:cast, {:handover, {transport, socket}}, :awaiting_socket, state) do
    new_state = %{state|transport: transport, socket: socket}
    next_action = {:next_event, :internal, :reset}
    {:next_state, :consume_length, new_state, next_action}
  end

  def handle_event(:cast, {:add_tokens, tokens}, _, state) do
    status = Allowance.set_tokens(state.status, tokens)
    next_event = [{:next_event, :internal, :consume}]
    {:keep_state, %{state|status: status}, next_event}
  end

  def handle_event(:internal, :reset, :consume_length, state) do
    status = Allowance.set_remaining(state.status, 4)
    next_event = [{:next_event, :internal, :consume}]
    {:keep_state, %{state|status: status}, next_event}
  end

  def handle_event(:internal, :consume, :consume_length, state) do
    case consume_bytes(state, @length_timeout) do
      # zero length message (awake)
      {:ok, {{<<0, 0, 0, 0>>, 0}, _} = status} ->
        {data, status} = Allowance.get_and_reset_buffer(status)
        :ok = emit(state, data)
        next_action = {:next_event, :internal, :reset}
        {:next_state, :consume_length, %{state|status: status}, next_action}

      # got a length, start receiving message
      {:ok, {{<<len::big-integer-size(32)>>, 0}, _} = status} ->
        updated_state = Allowance.set_remaining(status, len)
        next_action = {:next_event, :internal, :consume}
        {:next_state, :consume_message, %{state|status: updated_state}, next_action}

      # ran out of tokens, ask for more
      {:ok, {_continuation, 0} = status} ->
        new_state = %{state|status: status}
        :ok = request_tokens(new_state)
        {:keep_state, new_state}

      {:error, reason} ->
        {:stop, reason, state}
    end
  end

  def handle_event(:internal, :consume, :consume_message, state) do
    case consume_bytes(state, @message_timeout) do
      # done consuming message, emit and reset
      {:ok, {{_, 0}, _} = status} ->
        {data, new_state} = Allowance.get_and_reset_buffer(status)
        :ok = emit(state, data)
        next_action = [{:next_event, :internal, :reset}]
        {:next_state, :consume_length, %{state|status: new_state}, next_action}

      # ran out of tokens, ask for more
      {:ok, {_continuation, 0} = status} ->
        new_state = %{state|status: status}
        :ok = request_tokens(new_state)
        {:keep_state, new_state}

      # message is partially done, consume more
      {:ok, status} ->
        next_action = {:next_event, :internal, :consume}
        {:keep_state, %{state|status: status}, next_action}

      {:error, reason} ->
        {:stop, reason, state}
    end
  end

  #=HELPERS ==========================================================
  defp consume_bytes(%{status: {_continuation, 0} = state}, _timeout) do
    # we ran out of tokens
    {:ok, state}
  end
  defp consume_bytes(%{status: status} = state, timeout) do
    {tokens, status} = Allowance.take_tokens(status, @max_tokens_at_a_time)
    case apply(state.transport, :recv, [state.socket, tokens, timeout]) do
      {:ok, result} ->
        Allowance.write_buffer(status, result)

      # todo, handle various connection errors
      {:error, _reason} = error ->
        error
    end
  end

  defp emit(state, data) do
    Peer.Controller.receive_message(state.session, data)
  end

  defp request_tokens(%{status: {_, 0}} = state) do
    Peer.Controller.request_tokens(state.session, self)
  end
end
