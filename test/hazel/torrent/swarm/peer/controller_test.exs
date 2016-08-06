defmodule Hazel.Torrent.Swarm.Peer.ControllerTest do
  use ExUnit.Case

  alias Hazel.Torrent.Swarm.Peer.Controller
  alias Hazel.Torrent.Store.BitField

  defp generate_session(opts \\ [length: 200, piece_length: 10]) do
    local_id = Hazel.generate_peer_id()
    peer_id = Hazel.generate_peer_id()
    info_hash = :crypto.strong_rand_bytes(20)

    BitField.start_link(local_id, info_hash, Keyword.take(opts, [:length, :piece_length]))

    {{local_id, info_hash}, peer_id}
  end

  test "create a peer controller" do
    {session, peer_id} = generate_session()
    assert {:ok, pid} = Controller.start_link(session, peer_id, [])
  end
end
