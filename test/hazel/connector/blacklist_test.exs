defmodule Hazel.Connector.BlacklistTest do
  use ExUnit.Case, async: true

  import Hazel.TestHelpers, only: [generate_peer_id: 0]

  test "storing bad peers in blacklist" do
    local_id = generate_peer_id()
    {:ok, pid} = Hazel.Connector.Blacklist.start_link(local_id)

    :ok = Hazel.Connector.Blacklist.put(pid, "foo")
    assert Hazel.Connector.Blacklist.member?(pid, "foo")
    refute Hazel.Connector.Blacklist.member?(pid, "bar")
  end
end
