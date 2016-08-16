defmodule Hazel.PeerDiscovery.Controller do
  @moduledoc false
  use GenServer

  # Client API
  def start_link(default) do
    GenServer.start_link(__MODULE__, default)
  end

  # Server callbacks
  def init(state) do
    {:ok, state}
  end
end
