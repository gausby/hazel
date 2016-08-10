defmodule Hazel.AcceptorTest do
  use ExUnit.Case

  import Hazel.TestHelpers, only: [create_torrent_file: 2,
                                   encode_torrent_file: 1,
                                   create_acceptor: 1,
                                   create_handshake: 2]

  setup do
    file_data = :crypto.strong_rand_bytes(120)
    torrent_file = create_torrent_file(file_data, [piece_length: 30])
    dot_torrent = encode_torrent_file(torrent_file)
    {_, info_hash} = Bencode.decode_with_info_hash!(dot_torrent)

    peer_id = Hazel.generate_peer_id()

    %{peer_id: peer_id,
      info_hash: info_hash,
      file_data: file_data,
      torrent_file: torrent_file}
  end

  defp create_torrent_and_add_file(local_id, info_hash, opts) do
    opts = Keyword.merge(opts, [name: :ram])

    Hazel.Torrent.start_link(local_id)
    :gproc.await({:n, :l, {Hazel.Torrent, local_id}})

    Hazel.Torrent.add(local_id, info_hash, opts)
    :gproc.await({:n, :l, {Hazel.Torrent.Supervisor, local_id, info_hash}})
    :ok
  end

  describe "handshake" do
    test "a client should get disconnected when receiving an invalid handshake", context do
      local_id = context[:peer_id]
      info_hash = context[:info_hash]

      :ok = create_torrent_and_add_file(local_id, info_hash, context[:torrent_file])

      {ip, port} = create_acceptor(local_id)
      {:ok, connection} = :gen_tcp.connect(ip, port, active: false)

      :gen_tcp.send(connection, :crypto.strong_rand_bytes(68))
      assert {:error, :closed} = :gen_tcp.recv(connection, 68, 5000)
    end

    test "a client connects and performs a handshake", context do
      local_id = context[:peer_id]
      info_hash = context[:info_hash]

      :ok = create_torrent_and_add_file(local_id, info_hash, context[:torrent_file])

      {ip, port} = create_acceptor(local_id)
      {:ok, connection} = :gen_tcp.connect(ip, port, active: false)

      :gen_tcp.send(connection, create_handshake(Hazel.generate_peer_id(), info_hash))
      expected_handshake = IO.iodata_to_binary(create_handshake(local_id, info_hash))

      assert {:ok, actual_handshake} = :gen_tcp.recv(connection, 68, 5000)
      assert expected_handshake == IO.iodata_to_binary(actual_handshake)
    end
  end

  describe "handover" do
    test "a client should get connected to a swarm", context do
      local_id = context[:peer_id]
      info_hash = context[:info_hash]

      :ok = create_torrent_and_add_file(local_id, info_hash, context[:torrent_file])
      {ip, port} = create_acceptor(local_id)
      {:ok, connection} = :gen_tcp.connect(ip, port, active: false)

      peer_id = Hazel.generate_peer_id()
      :gen_tcp.send(connection, create_handshake(peer_id, info_hash))
      {:ok, _} = :gen_tcp.recv(connection, 68, 5000)
      {pid, _} = :gproc.await({:n, :l, {Hazel.Torrent.Swarm.Peer, local_id, info_hash, peer_id}}, 5000)
      assert is_pid(pid)
    end
  end
end
