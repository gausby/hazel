defmodule Hazel.Torrent.Supervisor do
  use Supervisor

  def start_link(peer_id, info_hash, opts) do
    Supervisor.start_link(__MODULE__, {peer_id, info_hash, opts}, name: via_name({peer_id, info_hash}))
  end

  defp via_name(session), do: {:via, :gproc, supervisor_name(session)}
  defp supervisor_name({peer_id, info_hash}), do: {:n, :l, {__MODULE__, peer_id, info_hash}}

  def init({peer_id, info_hash, opts}) do
    children = [
      supervisor(Hazel.Torrent.Store, [peer_id, info_hash, opts]),
      # supervise (Hazel.Torrent.Swarm, [peer_id, info_hash, opts]),
      worker(Hazel.Torrent.Controller, [peer_id, info_hash, opts])
    ]

    supervise(children, strategy: :one_for_one)
  end

  def where_is(session) do
    case :gproc.where(supervisor_name(session)) do
      :undefined ->
        {:error, :unknown_session}

      pid when is_pid(pid) ->
        {:ok, pid}
    end
  end
end
