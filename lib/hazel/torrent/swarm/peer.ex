defmodule Hazel.Torrent.Swarm.Peer do
  @moduledoc false

  use Supervisor

  alias Hazel.Torrent.Swarm.Peer.{Transmitter, Receiver, Controller}

  def start_link(local_id, info_hash, peer_id) do
    session = {local_id, info_hash}
    Supervisor.start_link(__MODULE__, {session, peer_id}, name: via_name(session, peer_id))
  end

  defp via_name(session, peer_id), do: {:via, :gproc, peer_name(session, peer_id)}
  defp peer_name({local_id, info_hash}, peer_id), do: {:n, :l, {__MODULE__, local_id, info_hash, peer_id}}

  defdelegate handover_socket(session, connection), to: Controller

  def init({session, peer_id}) do
    children = [
      worker(Receiver, [session, peer_id]),
      worker(Transmitter, [session, peer_id]),
      worker(Controller, [session, peer_id])
    ]
    supervise(children, strategy: :one_for_one)
  end
end
