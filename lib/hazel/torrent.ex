defmodule Hazel.Torrent do
  @moduledoc false

  use Supervisor

  def start_link(local_id) do
    Supervisor.start_link(__MODULE__, local_id, name: via_name(local_id))
  end

  defp via_name(local_id), do: {:via, :gproc, tracker_name(local_id)}
  defp tracker_name(local_id), do: {:n, :l, {__MODULE__, local_id}}

  def init(local_id) do
    children = [
      supervisor(Hazel.Torrent.Supervisor, [local_id])
    ]

    supervise(children, strategy: :simple_one_for_one)
  end

  @doc """
  Add a new torrent for download/upload
  """
  def add(local_id, info_hash, torrent) do
    Supervisor.start_child(via_name(local_id), [info_hash, torrent])
  end

  defdelegate where_is(session), to: Hazel.Torrent.Supervisor

  defdelegate request_peer(session, piece_index), to: Hazel.Torrent.Controller

  defdelegate broadcast_piece(session, piece_index), to: Hazel.Torrent.Controller
end
