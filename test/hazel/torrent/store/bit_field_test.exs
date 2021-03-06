defmodule Hazel.Torrent.Store.BitFieldTest do
  use ExUnit.Case, async: true
  doctest Hazel.Torrent.Store.BitField

  import Hazel.TestHelpers, only: [generate_peer_id: 0]

  alias Hazel.Torrent.Store.BitField

  setup do
    context =
      %{info_hash: :crypto.strong_rand_bytes(20),
        peer_id: generate_peer_id()}

    {:ok, context}
  end

  test "bit field integration test", %{info_hash: info_hash, peer_id: peer_id} do
    assert {:ok, _pid} = BitField.start_link(peer_id, info_hash, [length: 4, piece_length: 2])

    session = {peer_id, info_hash}

    assert :ok = BitField.have(session, 0)
    refute BitField.has_all?(session)
    assert :ok = BitField.have(session, 1)
    assert BitField.has_all?(session)
    assert [0, 1] == BitField.available(session)
  end
end
