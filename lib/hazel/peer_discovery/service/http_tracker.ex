defmodule Hazel.PeerDiscovery.Service.HttpTracker do
  @moduledoc false
  use Hazel.PeerDiscovery.Service
  use GenServer

  # Client API
  def start_link(session, opts) do
    GenServer.start_link(__MODULE__, opts, name: via_name({session, opts[:source]}))
  end

  # Server callbacks
  def init(state) do
    {:ok, state}
  end
end
