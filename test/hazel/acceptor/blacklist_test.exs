defmodule Hazel.Acceptor.BlacklistTest do
  use ExUnit.Case, async: true

  import Hazel.TestHelpers, only: [generate_peer_id: 0]

  test "storing bad peers in blacklist" do
    local_id = generate_peer_id()
    {:ok, pid} = Hazel.Acceptor.Blacklist.start_link(local_id)

    :ok = Hazel.Acceptor.Blacklist.put(pid, "foo")
    assert Hazel.Acceptor.Blacklist.member?(pid, "foo")
    refute Hazel.Acceptor.Blacklist.member?(pid, "bar")
  end
end
