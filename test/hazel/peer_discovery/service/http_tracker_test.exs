defmodule Hazel.PeerDiscovery.Service.HttpTrackerTest do
  use ExUnit.Case, async: true

  alias Hazel.PeerDiscovery.Service.HttpTracker

  test "start a HTTP tracker service" do
    session = generate_session()
    {:ok, _pid} = HttpTracker.start_link(session, source: "foo")
  end

  defp generate_session() do
    Hazel.generate_peer_id()
  end
end
