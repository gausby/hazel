defmodule Hazel.Torrent.Swarm.Peer.Transmitter do
  @moduledoc false

  use GenServer

  # Client API
  def start_link(session, peer_id) do
    GenServer.start_link(__MODULE__, peer_id, name: via_name({session, peer_id}))
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
    GenServer.cast(via_name(session), {:connection, connection})
  end

  # Server callbacks
  def init(state) do
    {:ok, state}
  end

  def handle_cast({:connection, {transport, socket}}, state) do
    new_state = %{transport: transport, socket: socket}
    {:noreply, new_state}
  end
end
