defmodule Hazel.Torrent.Store.FileTest do
  use ExUnit.Case, async: true
  doctest Hazel.Torrent.Store.File

  import Hazel.TestHelpers, only: [generate_peer_id: 0]

  alias Hazel.Torrent.Store

  setup do
    context =
      %{peer_id: generate_peer_id(),
        info_hash: :crypto.strong_rand_bytes(20)}

    {:ok, context}
  end

  describe "File handler reading and writing" do
    test "write bytes to a file", %{info_hash: info_hash, peer_id: peer_id} do
      hashes = IO.iodata_to_binary([:crypto.hash(:sha, "a")])
      opts = [length: 1, piece_length: 1, pieces: hashes, name: :ram]
      {:ok, _} = Store.File.start_link(peer_id, info_hash, opts)

      session = {peer_id, info_hash}
      assert :ok = Store.File.write_chunk(session, 0, 0, "a")
      assert "a" = Store.File.get_piece(session, 0)
    end

    test "write bytes to a file with multiple pieces", %{info_hash: info_hash, peer_id: peer_id} do
      hashes = IO.iodata_to_binary([:crypto.hash(:sha, "a"), :crypto.hash(:sha, "b")])
      opts = [length: 2, piece_length: 1, pieces: hashes, name: :ram]
      {:ok, _pid} = Store.File.start_link(peer_id, info_hash, opts)

      session = {peer_id, info_hash}
      assert :ok = Store.File.write_chunk(session, 0, 0, "a")
      assert :ok = Store.File.write_chunk(session, 1, 0, "b")
      assert "a" == Store.File.get_piece(session, 0)
      assert "b" == Store.File.get_piece(session, 1)
    end

    test "write bytes to a file with multi-byte pieces", %{info_hash: info_hash, peer_id: peer_id} do
      hashes = IO.iodata_to_binary([:crypto.hash(:sha, "abcd"), :crypto.hash(:sha, "efgh")])
      opts = [length: 8, piece_length: 4, pieces: hashes, name: :ram]
      {:ok, _pid} = Store.File.start_link(peer_id, info_hash, opts)

      session = {peer_id, info_hash}
      :ok = Store.File.write_chunk(session, 0, 0, "abcd")
      :ok = Store.File.write_chunk(session, 1, 0, "efgh")

      assert Store.File.get_piece(session, 0) == "abcd"
      assert Store.File.get_piece(session, 1) == "efgh"
    end

    test "write bytes to a file with multi byte piece lengths", %{info_hash: info_hash, peer_id: peer_id} do
      hashes = IO.iodata_to_binary([:crypto.hash(:sha, "abcd")])
      opts = [length: 4, piece_length: 4, pieces: hashes, name: :ram]
      {:ok, _pid} = Store.File.start_link(peer_id, info_hash, opts)

      session = {peer_id, info_hash}
      assert :ok = Store.File.write_chunk(session, 0, 0, "ab")
      assert :ok = Store.File.write_chunk(session, 0, 2, "cd")
      assert Store.File.get_piece(session, 0) == "abcd"
    end

    test "write bytes to the last piece with different piece length", %{info_hash: info_hash, peer_id: peer_id} do
      hashes = IO.iodata_to_binary([:crypto.hash(:sha, "abc"), :crypto.hash(:sha, "d")])
      opts = [length: 4, piece_length: 3, pieces: hashes, name: :ram]
      {:ok, _pid} = Store.File.start_link(peer_id, info_hash, opts)

      session = {peer_id, info_hash}
      assert :ok = Store.File.write_chunk(session, 0, 0, "abc")
      assert :ok = Store.File.write_chunk(session, 1, 0, "d")
      assert Store.File.get_piece(session, 0) == "abc"
      assert Store.File.get_piece(session, 1) == "d"
    end

    test "trying to read a non-existent piece index should result in an error", %{info_hash: info_hash, peer_id: peer_id} do
      hashes = IO.iodata_to_binary([:crypto.hash(:sha, "ab")])
      opts = [piece_length: 2, length: 2, pieces: hashes, name: :ram]
      {:ok, _pid} = Store.File.start_link(peer_id, info_hash, opts)

      session = {peer_id, info_hash}
      assert {:error, :out_of_bounds} = Store.File.get_piece(session, 2)
    end

    test "writing to a piece that does not exist should result in an error", %{info_hash: info_hash, peer_id: peer_id} do
      hashes = IO.iodata_to_binary([:crypto.hash(:sha, "a")])
      opts = [length: 1, piece_length: 1, pieces: hashes, name: :ram]
      {:ok, _pid} = Store.File.start_link(peer_id, info_hash, opts)

      session = {peer_id, info_hash}
      assert {:error, :out_of_bounds} = Store.File.write_chunk(session, 1, 0, "a")
    end

    test "writing outside the bounds of a piece should result in an error", %{info_hash: info_hash, peer_id: peer_id} do
      hashes = IO.iodata_to_binary([:crypto.hash(:sha, "a")])
      opts = [length: 1, piece_length: 1, pieces: hashes, name: :ram]
      {:ok, _pid} = Store.File.start_link(peer_id, info_hash, opts)

      session = {peer_id, info_hash}
      assert :ok = Store.File.write_chunk(session, 0, 0, "a")
      assert {:error, :out_of_piece_bounds} = Store.File.write_chunk(session, 0, 1, "b")
    end

    test "writing outside the bounds of a file should result in an error", %{info_hash: info_hash, peer_id: peer_id} do
      hashes = IO.iodata_to_binary([:crypto.hash(:sha, "a")])
      opts = [length: 1, piece_length: 1, pieces: hashes, name: :ram]
      {:ok, _pid} = Store.File.start_link(peer_id, info_hash, opts)

      session = {peer_id, info_hash}
      assert {:error, :out_of_bounds} = Store.File.write_chunk(session, 0, 0, "ab")
    end

    test "getting data with offset", %{info_hash: info_hash, peer_id: peer_id} do
      [one, two] = ["abcd", "efgh"]
      hashes = IO.iodata_to_binary([:crypto.hash(:sha, one), :crypto.hash(:sha, two)])
      opts = [piece_length: 4, length: 8, pieces: hashes, name: :ram]
      {:ok, _pid} = Store.File.start_link(peer_id, info_hash, opts)

      session = {peer_id, info_hash}
      :ok = Store.File.write_chunk(session, 0, 0, one)
      :ok = Store.File.write_chunk(session, 1, 0, two)
      assert {:ok, "bc"} == Store.File.get_chunk(session, 0, 1, 2)
      assert {:ok, "gh"} == Store.File.get_chunk(session, 1, 2, 2)
    end

    test "getting data out of bounds", %{info_hash: info_hash, peer_id: peer_id} do
      [one, two] = ["abcd", "efgh"]
      hashes = IO.iodata_to_binary([:crypto.hash(:sha, one), :crypto.hash(:sha, one)])
      opts = [piece_length: 4, length: 8, pieces: hashes, name: :ram]
      {:ok, _pid} = Store.File.start_link(peer_id, info_hash, opts)

      session = {peer_id, info_hash}
      :ok = Store.File.write_chunk(session, 0, 0, one)
      :ok = Store.File.write_chunk(session, 1, 0, two)
      assert {:error, :out_of_piece_bounds} = Store.File.get_chunk(session, 0, 3, 2)
    end
  end

  describe "File handler validating pieces" do
    test "invalid data should return false for piece validation", %{info_hash: info_hash, peer_id: peer_id} do
      hashes = IO.iodata_to_binary([:crypto.hash(:sha, "abcd")])
      opts = [piece_length: 4, length: 4, pieces: hashes, name: :ram]
      {:ok, _pid} = Store.File.start_link(peer_id, info_hash, opts)

      session = {peer_id, info_hash}
      :ok = Store.File.write_chunk(session, 0, 0, "ab")
      :ok = Store.File.write_chunk(session, 0, 2, "fo")
      assert false == Store.File.validate_piece(session, 0)
    end

    test "validate the last piece with a irregular length", %{info_hash: info_hash, peer_id: peer_id} do
      hashes = IO.iodata_to_binary([:crypto.hash(:sha, "abcd"),
                                    :crypto.hash(:sha, "ef")])
      opts = [piece_length: 4, length: 6, pieces: hashes, name: :ram]
      {:ok, _pid} = Store.File.start_link(peer_id, info_hash, opts)

      session = {peer_id, info_hash}
      :ok = Store.File.write_chunk(session, 1, 0, "ef")
      assert true == Store.File.validate_piece(session, 1)
    end
  end
end
