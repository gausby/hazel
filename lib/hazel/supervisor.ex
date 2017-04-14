defmodule Hazel.Supervisor do
  @moduledoc false

  use Supervisor

  @type local_id :: binary
  @type options :: [option]
  @type option ::
    {:port, integer()}

  @spec start_link(local_id, options) ::
    {:ok, pid} |
    :ignore |
    {:error, {:already_started, pid} | {:shutdown, term()} | term()}
  def start_link(<<local_id::binary-size(20)>>, opts \\ []) do
    Supervisor.start_link(__MODULE__, {local_id, opts}, name: via_name(local_id))
  end

  defp via_name(pid) when is_pid(pid), do: pid
  defp via_name(local_id), do: {:via, :gproc, reg_name(local_id)}
  defp reg_name(local_id), do: {:n, :l, {__MODULE__, local_id}}

  def init({local_id, opts}) do
    children = [
      # resource manager
      supervisor(Hazel.Connector, [local_id, opts]),
      supervisor(Hazel.PeerDiscovery, [local_id]),
      supervisor(Hazel.Torrent, [local_id])
    ]
    supervise(children, strategy: :one_for_one)
  end
end
