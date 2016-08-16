defmodule Hazel.PeerDiscovery do
  @moduledoc false
  use Supervisor

  alias Hazel.PeerDiscovery

  def start_link(local_id) do
    Supervisor.start_link(__MODULE__, local_id, name: via_name(local_id))
  end

  defp via_name(local_id), do: {:via, :gproc, reg_name(local_id)}
  defp reg_name(local_id), do: {:n, :l, {__MODULE__, local_id}}

  def init(session) do
    children = [
      supervisor(PeerDiscovery.Supervisor, [session]),
      worker(PeerDiscovery.Registry, [session]),
      worker(PeerDiscovery.Controller, [session])
    ]
    supervise(children, strategy: :one_for_one)
  end

  defdelegate add_service(session, mod, args), to: PeerDiscovery.Supervisor
end
