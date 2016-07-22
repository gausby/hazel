defmodule Hazel.Torrent.Swarm.Peer.Controller do
  @moduledoc false

  use GenServer
  alias Hazel.Torrent.Swarm.Peer.{Receiver, Transmitter}

  # Client API
  def start_link(session, peer_id) do
    GenServer.start_link(__MODULE__, peer_id, name: via_name(session, peer_id))
  end

  defp via_name(session, peer_id), do: {:via, :gproc, controller_name(session, peer_id)}
  defp controller_name({local_id, info_hash}, peer_id), do: {:n, :l, {__MODULE__, local_id, info_hash, peer_id}}

  def handover_socket(session, {transport, socket} = connection) do
    case Transmitter.where_is(session) do
      {:ok, pid} ->
        :ok = transport.controlling_process(socket, pid)
        :ok = Transmitter.handover_socket(pid, connection)
        # :ok = Receiver.handover_socket(session, peer_id, connection)

      {:error, _reason} = error ->
        error
    end
  end

  # Server callbacks
  def init(state) do
    {:ok, state}
  end
end
