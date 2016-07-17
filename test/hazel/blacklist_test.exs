defmodule Hazel.BlacklistTest do
  use ExUnit.Case, async: true

  test "storing bad peers in blacklist" do
    peer_id = Hazel.generate_peer_id()

    {:ok, _pid} = Hazel.Supervisor.start_link(peer_id, [])

    :ok = Hazel.Blacklist.put(peer_id, "hej")
    assert Hazel.Blacklist.member?(peer_id, "hej")
    refute Hazel.Blacklist.member?(peer_id, "hej2")
  end
end
