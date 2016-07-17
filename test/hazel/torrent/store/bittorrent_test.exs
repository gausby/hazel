defmodule Hazel.Torrent.Store.BitFieldTest do
  use ExUnit.Case
  doctest Hazel.Torrent.Store.BitField

  alias Hazel.Torrent.Store.BitField

  setup do
    context =
      %{info_hash: :crypto.strong_rand_bytes(20),
        peer_id: Hazel.generate_peer_id()}

    {:ok, context}
  end

  test "bit field integration test", %{info_hash: info_hash, peer_id: peer_id} do
    assert {:ok, _pid} = BitField.start_link(peer_id, info_hash, [length: 4, piece_length: 2])

    assert :ok = BitField.have(peer_id, info_hash, 0)
    refute BitField.has_all?(peer_id, info_hash)
    assert :ok = BitField.have(peer_id, info_hash, 1)
    assert BitField.has_all?(peer_id, info_hash)
    assert MapSet.new([0, 1]) == BitField.available(peer_id, info_hash)
  end
end
