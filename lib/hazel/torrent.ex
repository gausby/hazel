defmodule Hazel.Torrent do
  @moduledoc false

  use Supervisor

  def start_link(peer_id) do
    Supervisor.start_link(__MODULE__, peer_id, name: via_name(peer_id))
  end

  defp via_name(peer_id), do: {:via, :gproc, tracker_name(peer_id)}
  defp tracker_name(peer_id), do: {:n, :l, {__MODULE__, peer_id}}

  def init(peer_id) do
    children = [
      supervisor(Hazel.Torrent.Supervisor, [peer_id])
    ]

    supervise(children, strategy: :simple_one_for_one)
  end

  @doc """
  Add a peer to the a process
  """
  def add(peer_id, info_hash, torrent) do
    Supervisor.start_child(via_name(peer_id), [info_hash, torrent])
  end
end
