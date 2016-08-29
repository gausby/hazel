defmodule Hazel.TorrentTest do
  use ExUnit.Case, async: true

  import Hazel.TestHelpers, only: [generate_peer_id: 0]

  test "adding files" do
    local_id = generate_peer_id()
    {:ok, _pid} = Hazel.Torrent.start_link(local_id)

    hashes = IO.iodata_to_binary([:crypto.hash(:sha, "a")])
    info_hash = :crypto.strong_rand_bytes(20)
    opts = [length: 1, piece_length: 1, pieces: hashes, name: :ram]

    assert {:ok, _pid} = Hazel.Torrent.add(local_id, info_hash, opts)
  end
end
