defmodule Hazel.Acceptor.BlacklistTest do
  use ExUnit.Case, async: true

  test "storing bad peers in blacklist" do
    peer_id = Hazel.generate_peer_id()
    {:ok, _pid} = Hazel.Acceptor.Blacklist.start_link(peer_id)

    :ok = Hazel.Acceptor.Blacklist.put(peer_id, "foo")
    assert Hazel.Acceptor.Blacklist.member?(peer_id, "foo")
    refute Hazel.Acceptor.Blacklist.member?(peer_id, "bar")
  end
end
