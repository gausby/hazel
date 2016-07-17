defmodule Hazel.Torrent.Swarm do
  @moduledoc false

  use GenServer

  # Client API
  def start_link(peer_id, info_hash, opts) do
    GenServer.start_link(__MODULE__, opts, name: via_name(peer_id, info_hash))
  end

  defp via_name(peer_id, info_hash), do: {:via, :gproc, swarm_name(peer_id, info_hash)}
  defp swarm_name(peer_id, info_hash), do: {:n, :l, {__MODULE__, peer_id, info_hash}}

  def request_peer(peer_id, info_hash, piece_index) do
    GenServer.cast(via_name(peer_id, info_hash), {:request_peer, piece_index})
  end

  def broadcast_piece(peer_id, info_hash, piece_index) do
    GenServer.cast(via_name(peer_id, info_hash), {:broadcast_piece, piece_index})
  end

  # Server callbacks
  def init(state) do
    {:ok, state}
  end
end
