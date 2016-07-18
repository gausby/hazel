defmodule Hazel.Torrent.Swarm do
  @moduledoc false

  use GenServer

  @type peer_id :: binary
  @type info_hash :: binary
  @type session :: {peer_id, info_hash}

  # Client API
  def start_link(peer_id, info_hash, opts) do
    GenServer.start_link(__MODULE__, opts, name: via_name({peer_id, info_hash}))
  end

  defp via_name(session), do: {:via, :gproc, swarm_name(session)}
  defp swarm_name({peer_id, info_hash}), do: {:n, :l, {__MODULE__, peer_id, info_hash}}

  @spec request_peer(session, non_neg_integer) :: :ok
  def request_peer(session, piece_index) do
    GenServer.cast(via_name(session), {:request_peer, piece_index})
  end

  @spec broadcast_piece(session, non_neg_integer) :: :ok
  def broadcast_piece(session, piece_index) do
    GenServer.cast(via_name(session), {:broadcast_piece, piece_index})
  end

  # Server callbacks
  def init(state) do
    {:ok, state}
  end
end
