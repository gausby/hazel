defmodule Hazel.PeerDiscoveryTest do
  use ExUnit.Case, async: true

  alias Hazel.PeerDiscovery
  alias __MODULE__.TestService

  test "starting the peer discovery tree" do
    session = generate_session()
    assert {:ok, _pid} = generate_peer_discovery(session)
  end

  test "starting a service" do
    session = generate_session()
    assert {:ok, _pid} = generate_peer_discovery(session)

    assert {:ok, _pid} =
      PeerDiscovery.start_service(session, TestService, [foo: :bar])
  end

  defp generate_session() do
    Hazel.generate_peer_id()
  end

  defp generate_peer_discovery(session) do
    {:ok, _pid} = PeerDiscovery.start_link(session)
  end

  defmodule TestService do
    @moduledoc false
    use Hazel.PeerDiscovery.Service
    use GenServer

    # Client API
    def start_link(session, _opts) do
      GenServer.start_link(__MODULE__, session)
    end

    # Server callbacks
    def init(state) do
      {:ok, state}
    end
  end
end
