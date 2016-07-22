defmodule Hazel.PeerDiscovery do
  @moduledoc false
  use Supervisor

  def start_link(local_id) do
    Supervisor.start_link(__MODULE__, :ok, name: via_name(local_id))
  end

  defp via_name(local_id), do: {:via, :gproc, peer_discovery_name(local_id)}
  defp peer_discovery_name(local_id), do: {:n, :l, {__MODULE__, local_id}}

  def init(:ok) do
    children = [

    ]
    supervise(children, strategy: :one_for_one)
  end
end
