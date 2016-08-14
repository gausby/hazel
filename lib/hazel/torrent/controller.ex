defmodule Hazel.Torrent.Controller do
  @moduledoc false
  use GenServer

  alias Hazel.Torrent.Swarm.Query
  alias Hazel.Torrent.Swarm.Peer

  @type local_id :: binary
  @type info_hash :: binary
  @type session :: {local_id, info_hash}
  @type piece_index :: non_neg_integer

  defstruct session: nil

  # Client API
  def start_link(local_id, info_hash, _opts \\ []) do
    session = {local_id, info_hash}
    GenServer.start_link(__MODULE__, [session: session], name: via_name(session))
  end

  defp via_name(pid) when is_pid(pid), do: pid
  defp via_name(session), do: {:via, :gproc, controller_name(session)}
  defp controller_name({local_id, info_hash}), do: {:n, :l, {__MODULE__, local_id, info_hash}}

  @spec request_peer(pid | session, piece_index) :: :ok
  def request_peer(session, piece_index) do
    GenServer.cast(via_name(session), {:request_peer, piece_index})
  end

  @spec broadcast_piece(pid | session, piece_index) :: :ok
  def broadcast_piece(session, piece_index) do
    GenServer.cast(via_name(session), {:broadcast_piece, piece_index})
  end

  # Server callbacks
  def init(opts) do
    state = %__MODULE__{session: opts[:session]}
    {:ok, state}
  end

  def handle_cast({:broadcast_piece, piece_index}, state) do
    state.session
    |> Query.all()
    |> Stream.each(fn peer -> apply(Peer, :have, [peer, piece_index]) end)
    |> Stream.run()

    {:noreply, state}
  end
end
