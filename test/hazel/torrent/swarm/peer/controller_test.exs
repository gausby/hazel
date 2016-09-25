defmodule Hazel.Torrent.Swarm.Peer.ControllerTest do
  use ExUnit.Case, async: true

  import Hazel.TestHelpers, only: [generate_peer_id: 0]

  alias Hazel.Torrent.Swarm.Peer.Controller
  alias Hazel.Torrent.Store.BitField

  defp generate_session(opts \\ [length: 200, piece_length: 10]) do
    local_id = generate_peer_id()
    peer_id = generate_peer_id()
    info_hash = :crypto.strong_rand_bytes(20)

    BitField.start_link(local_id, info_hash, Keyword.take(opts, [:length, :piece_length]))

    {{local_id, info_hash}, peer_id}
  end

  test "create a peer controller" do
    {session, peer_id} = generate_session()
    assert {:ok, _pid} = Controller.start_link(session, peer_id, [])
  end

  test "initial state" do
    {session, peer_id} = generate_session()
    {:ok, pid} = Controller.start_link(session, peer_id, [])
    assert %Controller{} = status = Controller.status(pid)
    # Either we or the remote should be have interest on init
    refute status.peer_interested?
    # and both should choke each other
    assert status.peer_choking?
    # the remote should have an empty bit field
    assert BitFieldSet.empty?(status.bit_field)
  end

  test "changing choke status" do
    {session, peer_id} = generate_session()
    {:ok, pid} = Controller.start_link(session, peer_id, [])

    # initial state should be choking
    assert Controller.status(pid).choking?
    # stop choking
    Controller.outgoing(pid, {:choke, false})
    refute Controller.status(pid).choking?
    # start choking again
    Controller.outgoing(pid, {:choke, true})
    assert Controller.status(pid).choking?
  end

  test "changing interest" do
    {session, peer_id} = generate_session()
    {:ok, pid} = Controller.start_link(session, peer_id, [])

    # initial state should be not interested
    refute Controller.status(pid).interesting?
    # switch to interested state
    Controller.outgoing(pid, {:interest, true})
    assert Controller.status(pid).interesting?
    # switch to not interested again
    Controller.outgoing(pid, {:interest, false})
    refute Controller.status(pid).interesting?
  end

  test "remote changes interest in us" do
    {session, peer_id} = generate_session()
    {:ok, pid} = Controller.start_link(session, peer_id, [])

    # initial state should be not interested
    refute Controller.status(pid).peer_interested?
    # switch to interested state
    Controller.incoming(pid, {:interest, true})
    assert Controller.status(pid).peer_interested?
    # switch to not interested again
    Controller.incoming(pid, {:interest, false})
    refute Controller.status(pid).peer_interested?
  end

  test "remote changes choke status" do
    {session, peer_id} = generate_session()
    {:ok, pid} = Controller.start_link(session, peer_id, [])

    # initial state should be choking us
    assert Controller.status(pid).peer_choking?
    # switch to not choking
    Controller.incoming(pid, {:choke, false})
    refute Controller.status(pid).peer_choking?
    # switch back to choking again
    Controller.incoming(pid, {:choke, true})
    assert Controller.status(pid).peer_choking?
  end

  test "remote sends bit field information" do
    {session, peer_id} = generate_session()
    {:ok, pid} = Controller.start_link(session, peer_id, [])

    assert BitFieldSet.empty?(Controller.status(pid).bit_field)

    data = <<129, 5, 0>>
    Controller.incoming(pid, {:bit_field, data})

    bit_field = Controller.status(pid).bit_field
    refute BitFieldSet.empty?(bit_field)

    {:ok, expected} = BitFieldSet.new(data, 20)
    assert BitFieldSet.equal?(bit_field, expected)
  end

  test "remote updates bit field state" do
    {session, peer_id} = generate_session()
    {:ok, pid} = Controller.start_link(session, peer_id, [])

    assert BitFieldSet.empty?(Controller.status(pid).bit_field)
    Controller.incoming(pid, {:have, 5})
    refute BitFieldSet.empty?(Controller.status(pid).bit_field)
  end

  test "sending have message to remote" do
    # todo, test that the transmitter actually receive this message
    {session, peer_id} = generate_session()
    {:ok, pid} = Controller.start_link(session, peer_id, [])

    assert :ok = Controller.broadcast(pid, {:have, 1})
  end
end
