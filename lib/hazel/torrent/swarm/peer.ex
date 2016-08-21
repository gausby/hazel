defmodule Hazel.Torrent.Swarm.Peer do
  @moduledoc false

  use Supervisor

  alias Hazel.Torrent.Swarm.Peer.{Transmitter, Receiver, Controller}

  def start_link(session, opts, peer_id) do
    Supervisor.start_link(__MODULE__, {session, peer_id, opts}, name: via_name({session, peer_id}))
  end

  defp via_name(pid) when is_pid(pid), do: pid
  defp via_name(session), do: {:via, :gproc, reg_name(session)}
  defp reg_name({{local_id, info_hash}, peer_id}), do: {:n, :l, {__MODULE__, local_id, info_hash, peer_id}}

  defdelegate handover_socket(session, connection), to: Controller

  defdelegate broadcast(session, message), to: Controller

  def init({session, peer_id, opts}) do
    file_length = opts[:length]
    piece_length = opts[:piece_length]
    number_of_pieces =
      div(file_length, piece_length) + (if rem(file_length, piece_length), do: 0, else: 1)

    children = [
      worker(Receiver, [session, peer_id]),
      worker(Transmitter, [session, peer_id]),
      worker(Controller, [session, peer_id, [number_of_pieces: number_of_pieces]])
    ]
    supervise(children, strategy: :one_for_one)
  end
end
