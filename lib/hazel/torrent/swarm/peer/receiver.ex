defmodule Hazel.Torrent.Swarm.Peer.Receiver do
  @moduledoc false

  use GenStateMachine

  defstruct [:socket, :transport]
  alias __MODULE__

  # Client API
  def start_link(session, peer_id) do
    GenStateMachine.start_link(__MODULE__, {:awaiting_socket, %Receiver{}}, name: via_name({session, peer_id}))
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
    GenStateMachine.cast(via_name(session), {:handover, connection})
  end

  def handle_event(:cast, {:handover, {transport, socket}}, :awaiting_socket, state) do
    new_state = %Receiver{state|transport: transport, socket: socket}
    {:next_state, :awaiting_controller, new_state}
  end
end
