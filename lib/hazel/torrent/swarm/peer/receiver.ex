defmodule Hazel.Torrent.Swarm.Peer.Receiver do
  @moduledoc false

  use GenServer

  # Client API
  def start_link(session, peer_id) do
    GenServer.start_link(__MODULE__, peer_id, name: via_name(session, peer_id))
  end

  defp via_name(session, peer_id), do: {:via, :gproc, receiver_name(session, peer_id)}
  defp receiver_name({local_id, info_hash}, peer_id), do: {:n, :l, {__MODULE__, local_id, info_hash, peer_id}}

  def handover_socket(session, peer_id, connection) do
    GenServer.cast(via_name(session, peer_id), {:connection, connection})
  end

  # Server callbacks
  def init(_) do
    {:ok, %{}}
  end

  def handle_cast({:connection, {transport, socket}}, state) do
    new_state = %{transport: transport, socket: socket}
    {:noreply, new_state}
  end
end
