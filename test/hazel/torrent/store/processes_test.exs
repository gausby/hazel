defmodule PeerMock do
  use GenServer

  alias Hazel.Torrent.Store

  defstruct info_hash: nil, requests: []

  # Client API
  def start_link(info_hash) do
    GenServer.start_link(__MODULE__, %PeerMock{info_hash: info_hash})
  end
  def start(info_hash) do
    GenServer.start(__MODULE__, %PeerMock{info_hash: info_hash})
  end

  def send_data(pid, piece_index, offset, data) do
    GenServer.cast(pid, {:piece, piece_index, offset, data})
  end

  def requests(pid) do
    GenServer.call(pid, :requests)
  end

  def stop(pid) do
    GenServer.stop(pid, :normal, 1000)
  end

  # Server callbacks
  def init(state) do
    {:ok, state}
  end

  def handle_call(:requests, _from, state) do
    {:reply, Enum.reverse(state.requests), state}
  end

  def handle_cast({:piece, piece_index, offset, data}, state) do
    Store.Processes.Worker.send_data({state.info_hash, piece_index}, {offset, data})
    {:noreply, state}
  end

  def handle_info({:request, _, _, _} = request, state) do
    {:noreply, %{state|requests: [request|state.requests]}}
  end

  def handle_info(_message, state) do
    {:noreply, state}
  end
end

defmodule Hazel.Torrent.Store.ProcessesTest do
  use ExUnit.Case, async: true
  doctest Hazel.Torrent.Store.Processes

  alias Hazel.Torrent.Store
  alias Hazel.TestHelpers.FauxServer

  setup do
    context =
      %{local_id: Hazel.generate_peer_id(),
        info_hash: :crypto.strong_rand_bytes(20)}

    {:ok, context}
  end

  test "should request peers when disconnected", %{local_id: local_id, info_hash: info_hash} do
    parent = self
    request_peer_cb = fn
      piece_index, _state -> send parent, {:got_request, piece_index}
    end
    {:ok, _pid} =
      FauxServer.start_link(local_id, info_hash,
        [mod: Hazel.Torrent.Controller,
         cb: %{request_peer: request_peer_cb}])

    %{processes: _processes_pid} =
      create_processes(local_id, info_hash, "foobar", [piece_length: 3])

    # Ask for piece, should ask the swarm for peers
    Store.Processes.get_piece({local_id, info_hash}, 0)
    assert_receive {:got_request, 0}
    # When a peer is introduced to the swarm and then removed it
    # should request a new peer
    {:ok, peer_pid} = PeerMock.start_link(info_hash)
    Store.Processes.Worker.announce_peer({info_hash, 0}, peer_pid)
    PeerMock.stop(peer_pid)
    assert_receive {:got_request, 0}
  end

  test "should be able to receive data when connected", %{local_id: local_id, info_hash: info_hash} do
    parent = self
    request_peer_cb = fn piece_index, _state ->
      send parent, {:got_request, piece_index}
    end
    {:ok, _pid} =
      FauxServer.start_link(local_id, info_hash,
        [mod: Hazel.Torrent.Controller,
         cb: %{request_peer: request_peer_cb}])

    %{processes: _processes_pid} =
      create_processes(local_id, info_hash, "abcdefgh", [piece_length: 2])

    # Ask for piece, should ask the swarm for peers
    Store.Processes.get_piece({local_id, info_hash}, 0)
    assert_receive {:got_request, 0}

    {:ok, peer_pid} = PeerMock.start_link(info_hash)
    :ok = Store.Processes.Worker.announce_peer({info_hash, 0}, peer_pid)
    :ok = PeerMock.send_data(peer_pid, 0, 0, "ab")
    :timer.sleep 100
    assert {:ok, "ab"} = Hazel.Torrent.Store.File.get_chunk({local_id, info_hash}, 0, 0, 2)
  end

  test "should send \"have\" to the controller when piece is complete and verified",
    %{local_id: local_id, info_hash: info_hash} do
    parent = self()
    request_peer_cb = fn piece_index, _state ->
      send parent, {:got_request, piece_index}
    end
    broadcast_piece_cb = fn piece_index, _state ->
      send parent, {:broadcast_piece, piece_index}
    end
    {:ok, _pid} =
      FauxServer.start_link(local_id, info_hash,
        [mod: Hazel.Torrent.Controller,
         cb: %{request_peer: request_peer_cb,
               broadcast_piece: broadcast_piece_cb}])

    %{} = create_processes(local_id, info_hash, "abcdefgh", [piece_length: 8, chunk_size: 4])

    # Ask for piece, should ask the swarm for peers
    {:ok, pid} = Store.Processes.get_piece({local_id, info_hash}, 0)
    assert_receive {:got_request, 0}

    # create peer, announce it, and send data
    {:ok, peer_pid} = PeerMock.start_link(info_hash)
    :ok = Store.Processes.Worker.announce_peer({info_hash, 0}, peer_pid)
    PeerMock.send_data(peer_pid, 0, 0, "abcd")
    PeerMock.send_data(peer_pid, 0, 4, "efgh")
    # the manager should receive a note about us having the piece, and
    # the download process should be terminated
    assert_receive {:broadcast_piece, 0}
    :timer.sleep 100
    refute Process.alive? pid
  end

  test "should fetch data from another peer if data is invalid",
    %{local_id: local_id, info_hash: info_hash} do
    parent = self()
    request_peer_cb = fn piece_index, _state ->
      send parent, {:got_request, piece_index}
    end
    broadcast_piece_cb = fn piece_index, _state ->
      send parent, {:broadcast_piece, piece_index}
    end
    {:ok, _pid} =
      FauxServer.start_link(local_id, info_hash,
        [mod: Hazel.Torrent.Controller,
         cb: %{request_peer: request_peer_cb,
               broadcast_piece: broadcast_piece_cb}])


    %{} = create_processes(local_id, info_hash, "abcdefgh", [piece_length: 8, chunk_size: 8])

    # Ask for piece, should ask the swarm for peers
    {:ok, _pid} = Store.Processes.get_piece({local_id, info_hash}, 0)
    assert_receive {:got_request, 0}

    # create peer, announce it, and send incorrect data
    {:ok, peer_pid} = PeerMock.start_link(info_hash)
    :ok = Store.Processes.Worker.announce_peer({info_hash, 0}, peer_pid)
    PeerMock.send_data(peer_pid, 0, 0, "abdcefhg")
    refute_receive {:broadcast_piece, 0}
    assert_receive {:got_request, 0}

    # create a new peer, announce it and send the correct data
    {:ok, peer_pid2} = PeerMock.start_link(info_hash)
    :ok = Store.Processes.Worker.announce_peer({info_hash, 0}, peer_pid2)

    PeerMock.send_data(peer_pid2, 0, 0, "abcdefgh")
    assert_receive {:broadcast_piece, 0}
  end

  test "should continue fetching data from another peer if connection is dropped",
    %{local_id: local_id, info_hash: info_hash} do
    parent = self()
    request_peer_cb =
      fn piece_index, _state -> send parent, {:got_request, piece_index} end
    broadcast_piece_cb =
      fn piece_index, _state -> send parent, {:broadcast_piece, piece_index} end
    {:ok, _pid} =
      FauxServer.start_link(local_id, info_hash,
        [mod: Hazel.Torrent.Controller,
         cb: %{request_peer: request_peer_cb,
               broadcast_piece: broadcast_piece_cb}])

    %{} = create_processes(local_id, info_hash, "abcdefgh", [piece_length: 8, chunk_size: 2])

    # Ask for piece, should ask the swarm for peers
    {:ok, pid} = Store.Processes.get_piece({local_id, info_hash}, 0)
    assert_receive {:got_request, 0}

    # create peer, announce it, and send incorrect data
    {:ok, peer_pid} = PeerMock.start(info_hash)
    :ok = Store.Processes.Worker.announce_peer({info_hash, 0}, peer_pid)
    PeerMock.send_data(peer_pid, 0, 0, "ab")
    PeerMock.send_data(peer_pid, 0, 2, "cd")
    :timer.sleep 100
    Process.exit(peer_pid, :kill)
    assert_receive {:got_request, 0}

    # create a new peer, announce it and send the correct data
    {:ok, peer_pid2} = PeerMock.start_link(info_hash)
    :ok = Store.Processes.Worker.announce_peer({info_hash, 0}, peer_pid2)
    PeerMock.send_data(peer_pid2, 0, 4, "ef")
    PeerMock.send_data(peer_pid2, 0, 6, "gh")

    assert_receive {:broadcast_piece, 0}
    :timer.sleep 100
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
      Store.Processes.start_link(local_id, info_hash, opts)

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
