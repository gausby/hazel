defmodule Hazel.Torrent.Store.Piece do
  use GenStateMachine

  @ideal_chunk_size 16 * 1024
  @type request :: {:request, non_neg_integer, non_neg_integer, non_neg_integer}

  defstruct [session: nil,
             plan: [],
             awaiting: [],
             completed: [],
             piece_number: nil,
             concurrent_requests: 5,
             peer: nil,
             manager: nil]

  alias __MODULE__, as: State
  alias Hazel.Torrent
  alias Hazel.Torrent.Store

  # Client API =======================================================
  def start_link(local_id, info_hash, piece_info, piece_number) do
    session = {local_id, info_hash}
    chunk_size = Keyword.get(piece_info, :chunk_size, @ideal_chunk_size)
    piece_length =
      if piece_number < piece_info[:number_of_pieces],
        do: piece_info[:piece_length],
        else: piece_info[:last_piece_length] || piece_info[:piece_length]

    plan = create_requests(piece_number, piece_length, chunk_size)
    state =
      %State{session: session,
             piece_number: piece_number,
             plan: plan,
             awaiting: [],
             completed: [],
             manager: Keyword.get(piece_info, :manager)}

    GenStateMachine.start_link(__MODULE__, state, name: via_name({session, piece_number}))
  end

  defp via_name(pid) when is_pid(pid), do: pid
  defp via_name(session), do: {:via, :gproc, reg_name(session)}
  defp reg_name({{local_id, info_hash}, piece_number}), do: {:n, :l, {__MODULE__, local_id, info_hash, piece_number}}

  def announce_peer({session, piece_number}, peer_pid) when is_pid(peer_pid) do
    GenStateMachine.cast(via_name({session, piece_number}), {:peer, peer_pid})
  end

  def write_chunk(session, piece_number, offset, data) do
    GenStateMachine.call(via_name({session, piece_number}), {:retrieving, offset, data})
  end

  #=Server callbacks =================================================
  @doc false
  def init(%State{} = state) do
    next_event = {:next_event, :internal, :request_peer}
    {:ok, :disconnected, state, next_event}
  end

  #=States -----------------------------------------------------------

  # We will monitor the peer that we are currently receiving data
  # from. If the peer process should disappear we will go back to
  # disconnected state and request a new peer
  @doc false
  def handle_event(:info, {:DOWN, _ref, :process, _pid, _reason}, :connected, state) do
    new_state =
      reset_awaiting(%{state|peer: nil})

    next_event = {:next_event, :internal, :request_peer}
    {:next_state, :disconnected, new_state, next_event}
  end

  # The process is not connected to a peer
  def handle_event(:internal, :request_peer, :disconnected,
    %State{peer: nil,
           session: session,
           piece_number: piece_number} = state) do
    :ok = Torrent.request_peer(session, piece_number)
    {:next_state, :awaiting_peer, state}
  end

  def handle_event(:cast, {:peer, peer_pid}, :awaiting_peer, %State{peer: nil} = state) do
    ref = Process.monitor(peer_pid)
    new_state = %{state|peer: {ref, peer_pid}}
    next_event = {:next_event, :internal, :request_chunks}
    {:next_state, :connected, new_state, next_event}
  end

  def handle_event(:internal, :request_chunks, :connected, state) do
    # request chunks, add to awaiting
    {requests, plan} =
      Enum.split(state.plan, state.concurrent_requests - length(state.awaiting))

    {_ref, peer} = state.peer
    for request <- requests, do: send peer, request

    {:keep_state, %{state|awaiting: state.awaiting ++ requests,
                          plan: plan}}
  end

  def handle_event({:call, from}, {:retrieving, offset, data}, :connected, state) do
    chunk_request =
      {:request, state.piece_number, offset, byte_size(data)}

    if chunk_request in state.awaiting do
      :ok = Store.File.write_chunk(state.session, state.piece_number, offset, data)

      new_state =
        %{state|awaiting: state.awaiting -- [chunk_request],
                completed: [{state.peer, chunk_request}|state.completed]}

      what_next(new_state, from)
    else
      # raise, stop or disconnect? We received something we didn't
      # expect; we should consider this a protocol violation.
      {:keep_state, state}
    end
  end

  defp discard_foreign_chunks(state) do
    own = state.peer
    Enum.reduce(state.completed, {[], state.plan}, fn
      {^own, _} = a, {completed, plan} ->
        {[a|completed], plan}

      {_, request}, {completed, plan} ->
        {completed, [request|plan]}
    end)
  end

  defp what_next(%{plan: [], awaiting: []} = state, from) do
    if Store.File.validate_piece(state.session, state.piece_number) do
      :ok = Store.BitField.have(state.session, state.piece_number)
      # should this be handled by the swarm controller?
      :ok = Torrent.broadcast_piece(state.session, state.piece_number)
      reply = {:reply, from, :ok}
      {:stop_and_reply, :normal, reply, state}
    else
      # todo: keep track of the chunks that has been written by the
      # current peer and put the foreign ones back into the plan and
      # start downloading them

      # figure out if all the pieces are of the same origin
      case discard_foreign_chunks(state) do
        {completed, []} ->
          # all chunks was from the current peer, reset to plan and
          # drop the peer and get ready to connect to a new one
          incomplete =
            for({_, request} <- completed, do: request)
            |> Enum.sort_by(&(elem(&1, 2)))

          new_state = %{state|peer: nil, plan: incomplete, completed: []}
          next_event =
            [{:reply, from, {:error, :invalid_data}},
             {:next_event, :internal, :request_peer}]

          {:next_state, :disconnected, new_state, next_event}

        {completed, incomplete} ->
          # some chunks was not from the peer, reschedule them and
          # request them from the peer
          new_state = %{state|plan: incomplete, completed: completed}
          next_event = {:next_event, :internal, :request_chunks}
          {:keep_state, new_state, next_event}
      end
    end
  end
  defp what_next(%{awaiting: []} = state, from) do
    next_event = [{:reply, from, :ok}, {:next_event, :internal, :request_chunks}]
    {:keep_state, state, next_event}
  end
  defp what_next(state, from) do
    next_event = {:reply, from, :ok}
    {:keep_state, state, next_event}
  end

  #=Helpers ==========================================================

  # Put the chunks we are awaiting back in the plan list and sort them
  # by their offset
  defp reset_awaiting(state) do
    plan =
      (state.plan ++ state.awaiting)
      |> Enum.sort_by(&(elem(&1, 2)))

    %{state|plan: plan, awaiting: []}
  end

  defp create_requests(piece_number, piece_length, chunk_size) do
    chunks = do_split_in_chunks(piece_length, chunk_size, 0, [])
    for {offset, chunk_length} <- chunks do
      {:request, piece_number, offset, chunk_length}
    end
  end

  defp do_split_in_chunks(0, _chunk_size, _offset, acc) do
    Enum.reverse(acc)
  end
  defp do_split_in_chunks(remainder, chunk_size, offset, acc)
  when remainder - chunk_size > 0 do
    new_remainder = remainder - chunk_size
    new_offset = offset + chunk_size
    do_split_in_chunks(new_remainder, chunk_size, new_offset, [{offset, chunk_size}|acc])
  end
  defp do_split_in_chunks(remainder, chunk_size, offset, acc) do
    do_split_in_chunks(0, chunk_size, remainder, [{offset, remainder}|acc])
  end
end
