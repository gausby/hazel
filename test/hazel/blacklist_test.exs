defmodule Hazel.Acceptor.BlacklistTest do
  use ExUnit.Case, async: true

  test "storing bad peers in blacklist" do
    local_id = Hazel.generate_peer_id()
    {:ok, _pid} = Hazel.Acceptor.Blacklist.start_link(local_id)

    :ok = Hazel.Acceptor.Blacklist.put(local_id, "foo")
    assert Hazel.Acceptor.Blacklist.member?(local_id, "foo")
    refute Hazel.Acceptor.Blacklist.member?(local_id, "bar")
  end
end
