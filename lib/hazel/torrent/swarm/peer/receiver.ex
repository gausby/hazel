defmodule Hazel.Torrent.Swarm.Peer.Receiver do
  @moduledoc false

  use GenServer

  defstruct [:socket, :transport]
  alias __MODULE__

  # Client API
  def start_link(session, peer_id) do
    GenServer.start_link(__MODULE__, %Receiver{}, name: via_name({session, peer_id}))
  end

  defp via_name(pid) when is_pid(pid), do: pid
  defp via_name({session, peer_id}), do: {:via, :gproc, receiver_name({session, peer_id})}
  defp receiver_name({{local_id, info_hash}, peer_id}), do: {:n, :l, {__MODULE__, local_id, info_hash, peer_id}}

  def where_is(session) do
    case :gproc.where(receiver_name(session)) do
      :undefined ->
        {:error, :unknown_peer_receiver}

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
    new_state = %Receiver{state|transport: transport, socket: socket}
    {:noreply, new_state}
  end
end
