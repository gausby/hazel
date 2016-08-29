defmodule Hazel.PeerDiscovery.Service.HttpTrackerTest do
  use ExUnit.Case, async: true

  alias Hazel.PeerDiscovery.Service.HttpTracker

  import Hazel.TestHelpers, only: [generate_peer_id: 0]

  test "start a HTTP tracker service" do
    session = generate_peer_id()
    {:ok, _pid} = HttpTracker.start_link(session, source: "foo")
  end
end
