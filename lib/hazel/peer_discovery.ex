defmodule Hazel.PeerDiscovery do
  @moduledoc false
  use Supervisor

  def start_link(peer_id) do
    Supervisor.start_link(__MODULE__, :ok, name: via_name(peer_id))
  end

  defp via_name(peer_id), do: {:via, :gproc, peer_discovery_name(peer_id)}
  defp peer_discovery_name(peer_id), do: {:n, :l, {__MODULE__, peer_id}}

  def init(:ok) do
    children = [

    ]
    supervise(children, strategy: :one_for_one)
  end
end
