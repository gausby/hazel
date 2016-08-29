defmodule Hazel.Torrent.Supervisor do
  use Supervisor

  def start_link(local_id, info_hash, opts) do
    Supervisor.start_link(__MODULE__, {local_id, info_hash, opts}, name: via_name({local_id, info_hash}))
  end

  defp via_name(pid) when is_pid(pid), do: pid
  defp via_name(session), do: {:via, :gproc, reg_name(session)}

  @doc false
  def reg_name({local_id, info_hash}), do: {:n, :l, {__MODULE__, local_id, info_hash}}

  def init({local_id, info_hash, opts}) do
    children = [
      supervisor(Hazel.Torrent.Store, [local_id, info_hash, opts]),
      supervisor(Hazel.Torrent.Swarm, [local_id, info_hash, opts]),
      worker(Hazel.Torrent.Controller, [local_id, info_hash, opts])
    ]

    supervise(children, strategy: :one_for_one)
  end

  def where_is(session) do
    case :gproc.where(reg_name(session)) do
      :undefined ->
        {:error, :unknown_session}

      pid when is_pid(pid) ->
        {:ok, pid}
    end
  end
end
