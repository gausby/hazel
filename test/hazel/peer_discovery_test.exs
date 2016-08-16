defmodule Hazel.PeerDiscoveryTest do
  use ExUnit.Case, async: true

  alias Hazel.PeerDiscovery

  test "starting the peer discovery tree" do
    session = generate_session()
    assert {:ok, _pid} = generate_peer_discovery(session)
  end

  defp generate_session() do
    Hazel.generate_peer_id()
  end

  defp generate_peer_discovery(session) do
    {:ok, _pid} = PeerDiscovery.start_link(session)
  end
end
