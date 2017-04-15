defmodule Hazel.Torrent.Store.PieceTest do
  use ExUnit.Case, async: true
  doctest Hazel.Torrent.Store.Piece.Supervisor

  import Hazel.TestHelpers, only: [generate_peer_id: 0]

  alias Hazel.Torrent.Store
  alias Hazel.Torrent.Swarm.Peer
  alias Hazel.TestHelpers.FauxServer

  setup do
    context =
      %{local_id: generate_peer_id(),
        info_hash: :crypto.strong_rand_bytes(20)}

    {:ok, context}
  end

  defp torrent_controller_via_name({local_id, info_hash}) do
    {Hazel.Torrent.Controller, local_id, info_hash}
  end

  test "should request peers when disconnected", %{local_id: local_id, info_hash: info_hash} do
    session = {local_id, info_hash}

    FauxServer.start_link(
      torrent_controller_via_name(session),
      [cb: [
          request_peer:
          fn piece_index, state ->
            send state[:pid], {:got_request, piece_index}
            :ok
          end]])

    %{processes: _processes_pid} =
      create_processes(local_id, info_hash, "foobar", [piece_length: 3])

    # Ask for piece, should ask the swarm for peers
    Store.get_piece(session, 0)
    assert_receive {:got_request, 0}
    # When a peer is introduced to the swarm and then removed it
    # should request a new peer
    {:ok, peer_pid} =
      FauxServer.start_link(
        Peer.Controller.reg_name({session, generate_peer_id()})
      )

    Store.Piece.announce_peer({session, 0}, peer_pid)
    Process.unlink(peer_pid)
    Process.exit(peer_pid, :kill)
    assert_receive {:got_request, 0}
  end

  test "should be able to receive data when connected", %{local_id: local_id, info_hash: info_hash} do
    session = {local_id, info_hash}

    FauxServer.start_link(
      torrent_controller_via_name(session),
      [cb: [
          request_peer:
          fn piece_index, state ->
            send state[:pid], {:got_request, piece_index}
            :ok
          end]])

    %{processes: _processes_pid} =
      create_processes(local_id, info_hash, "abcdefgh", [piece_length: 2])

    # Ask for piece, should ask the swarm for peers
    {:ok, _pid} = Store.get_piece(session, 0)
    assert_receive {:got_request, 0}

    {:ok, peer_pid} =
      FauxServer.start_link(
        Peer.Controller.reg_name({session, generate_peer_id()}),
        [cb: [
            receive:
            fn {:piece, piece_index, offset, data}, state ->
              send state[:pid], {:write_result, Store.write_chunk(session, piece_index, offset, data)}
              :ok
            end]])

    :ok = Store.Piece.announce_peer({session, 0}, peer_pid)

    :ok = Peer.Controller.incoming(peer_pid, {:piece, 0, 0, "ab"})
    assert_receive {:write_result, :ok}
    assert {:ok, "ab"} = Hazel.Torrent.Store.File.get_chunk(session, 0, 0, 2)
  end

  test "should send \"have\" to the controller when piece is complete and verified",
    %{local_id: local_id, info_hash: info_hash} do
    session = {local_id, info_hash}

    FauxServer.start_link(
      torrent_controller_via_name(session),
      [cb: [
          request_peer:
          fn piece_index, state ->
            send state[:pid], {:got_request, piece_index}
            :ok
          end,

          broadcast:
          fn message, state ->
            send state[:pid], {:broadcast, message}
            :ok
          end]])

    %{} = create_processes(local_id, info_hash, "abcdefgh", [piece_length: 8, chunk_size: 4])

    # Ask for piece, should ask the swarm for peers
    {:ok, pid} = Store.get_piece(session, 0)
    assert_receive {:got_request, 0}

    # create peer, announce it, and send data
    {:ok, peer_pid} =
      FauxServer.start_link(
        Peer.Controller.reg_name({session, generate_peer_id()}),
        [cb: [
            receive:
            fn {:piece, piece_index, offset, data}, _state ->
              :ok = Store.write_chunk(session, piece_index, offset, data)
            end]])

    :ok = Store.Piece.announce_peer({session, 0}, peer_pid)
    :ok = Peer.Controller.incoming(peer_pid, {:piece, 0, 0, "abcd"})
    :ok = Peer.Controller.incoming(peer_pid, {:piece, 0, 4, "efgh"})
    # the manager should receive a note about us having the piece, and
    # the download process should be terminated
    assert_receive {:broadcast, {:have, 0}}
    :timer.sleep(20) # TODO: The following test fails from time to time without the timeout
    refute Process.alive? pid
  end

  test "should fetch data from another peer if data is invalid",
    %{local_id: local_id, info_hash: info_hash} do
    session = {local_id, info_hash}

    FauxServer.start_link(
      torrent_controller_via_name(session),
      [cb: [
          request_peer:
          fn piece_index, state ->
            send state[:pid], {:got_request, piece_index}
            :ok
          end,

          broadcast:
          fn piece_index, state ->
            send state[:pid], {:broadcast, piece_index}
            :ok
          end]])

    %{} = create_processes(local_id, info_hash, "abcdefgh", [piece_length: 8, chunk_size: 8])

    # Ask for piece, should ask the swarm for peers
    {:ok, _pid} = Store.get_piece(session, 0)
    assert_receive {:got_request, 0}

    # create peer, announce it, and send incorrect data
    receive_callback =
      fn {:piece, piece_index, offset, data}, state ->
        send(
          state[:pid],
          {:write_result, Store.write_chunk(session, piece_index, offset, data)}
        )
        :ok
      end
    {:ok, peer_pid} =
      FauxServer.start_link(
        Peer.Controller.reg_name({session, generate_peer_id()}),
        [cb: [receive: receive_callback]])
    :ok = Store.Piece.announce_peer({session, 0}, peer_pid)
    :ok = Peer.Controller.incoming(peer_pid, {:piece, 0, 0, "abdcefhg"})

    assert_receive {:write_result, {:error, :invalid_data}}
    refute_receive {:broadcast_piece, 0}
    assert_receive {:got_request, 0}

    # create a new peer, announce it, and send the correct data
    {:ok, peer_pid2} =
      FauxServer.start_link(
        Peer.Controller.reg_name({session, generate_peer_id()}),
        [cb: [receive: receive_callback]])
    :ok = Store.Piece.announce_peer({session, 0}, peer_pid2)
    :ok = Peer.Controller.incoming(peer_pid2, {:piece, 0, 0, "abcdefgh"})

    assert_receive {:write_result, :ok}
    assert_receive {:broadcast, {:have, 0}}
  end

  test "should continue fetching data from another peer if connection is dropped",
    %{local_id: local_id, info_hash: info_hash} do
    session = {local_id, info_hash}

    FauxServer.start_link(
      torrent_controller_via_name(session),
      [cb: [
          request_peer:
          fn piece_index, state ->
            send state[:pid], {:got_request, piece_index}
            :ok
          end,

          broadcast:
          fn message, state ->
            send state[:pid], {:broadcast, message}
            :ok
          end]])

    %{} = create_processes(local_id, info_hash, "abcdefgh", [piece_length: 8, chunk_size: 2])

    # Ask for piece, should ask the swarm for peers
    {:ok, pid} = Store.get_piece(session, 0)
    assert_receive {:got_request, 0}

    receive_callback = fn {:piece, piece_index, offset, data}, state ->
      send(
        state[:pid],
        {:write_result, Store.write_chunk(session, piece_index, offset, data)}
      )
      :ok
    end

    # create peer, announce it, and send some of the data
    {:ok, peer_pid} =
      FauxServer.start_link(
        Peer.Controller.reg_name({session, generate_peer_id()}),
        [cb: [receive: receive_callback]])

    :ok = Store.Piece.announce_peer({session, 0}, peer_pid)
    :ok = Peer.Controller.incoming(peer_pid, {:piece, 0, 0, "ab"})
    assert_receive {:write_result, :ok}
    :ok = Peer.Controller.incoming(peer_pid, {:piece, 0, 2, "cd"})
    assert_receive {:write_result, :ok}
    # kill the peer
    true = Process.unlink(peer_pid)
    Process.exit(peer_pid, :kill)
    assert_receive {:got_request, 0}

    # create a new peer, announce it and send the rest of the data
    {:ok, peer_pid2} =
      FauxServer.start_link(
        Peer.Controller.reg_name({session, generate_peer_id()}),
        [cb: [receive: receive_callback]])

    :ok = Store.Piece.announce_peer({session, 0}, peer_pid2)
    :ok = Peer.Controller.incoming(peer_pid2, {:piece, 0, 4, "ef"})
    assert_receive {:write_result, :ok}
    :ok = Peer.Controller.incoming(peer_pid2, {:piece, 0, 6, "gh"})
    assert_receive {:write_result, :ok}

    assert_receive {:broadcast, {:have, 0}}
    refute Process.alive?(pid)
  end

  # HELPERS ----------------------------------------------------------
  defp create_processes(local_id, info_hash, data, opts) do
    hashes =
      for piece <- split_pieces(data, opts[:piece_length]),
        do: :crypto.hash(:sha, piece)

    opts = Keyword.put(opts, :length, byte_size(data))
    file_opts =
      Keyword.merge(opts, name: :ram, pieces: IO.iodata_to_binary(hashes))

    {:ok, file_pid} =
      Store.File.start_link(local_id, info_hash, file_opts)
    {:ok, bitfield_pid} =
      Store.BitField.start_link(local_id, info_hash, opts)
    {:ok, processes_pid} =
      Store.Piece.Supervisor.start_link(local_id, info_hash, opts)

    %{hashes: hashes,
      file: file_pid,
      bitfield: bitfield_pid,
      processes: processes_pid}
  end

  defp split_pieces(data, piece_index, acc \\ [])
  defp split_pieces(<<>>, _, acc) do
    Enum.reverse(acc)
  end
  defp split_pieces(data, piece_length, acc) do
    <<data::binary-size(piece_length), rest::binary>> = data
    split_pieces(rest, piece_length, [data|acc])
  end
end
