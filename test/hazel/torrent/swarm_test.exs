defmodule Hazel.Torrent.SwarmTest do
  use ExUnit.Case, async: true

  import Hazel.TestHelpers, only: [generate_peer_id: 0]

  alias Hazel.Torrent.Swarm
  alias Hazel.Torrent.Swarm.Peer.Controller
  alias Hazel.Torrent.Store.BitField

  defp generate_session(opts \\ [length: 200, piece_length: 10]) do
    local_id = generate_peer_id()
    info_hash = :crypto.strong_rand_bytes(20)

    BitField.start_link(local_id, info_hash, Keyword.take(opts, [:length, :piece_length]))

    {local_id, info_hash}
  end

  defp generate_peer(session, orders) do
    orders = Keyword.merge([incoming: [], outgoing: []], orders)
    peer_id = generate_peer_id()
    {:ok, pid} = Controller.start_link(session, peer_id, [])
    Enum.each(orders[:incoming], &(Controller.incoming(pid, &1)))
    Enum.each(orders[:outgoing], &(Controller.outgoing(pid, &1)))
    :timer.sleep 10
    {:ok, pid}
  end

  test "query for interested peers" do
    session = generate_session()
    {:ok, pid1} = generate_peer(session, incoming: [{:interest, true}])
    {:ok, pid2} = generate_peer(session, incoming: [{:interest, false}])
    {:ok, pid3} = generate_peer(session, incoming: [{:interest, true}])

    result = Swarm.Query.interested_peers(session)

    assert pid1 in result
    refute pid2 in result
    assert pid3 in result
  end

  test "query for peer we have marked as interesting" do
    session = generate_session()
    {:ok, pid1} = generate_peer(session, outgoing: [{:interest, true}])
    {:ok, pid2} = generate_peer(session, outgoing: [{:interest, false}])
    {:ok, pid3} = generate_peer(session, outgoing: [{:interest, true}])

    result = Swarm.Query.interesting_peers(session)

    assert pid1 in result
    refute pid2 in result
    assert pid3 in result
  end

  test "query for choking peers" do
    session = generate_session()
    {:ok, pid1} = generate_peer(session, incoming: [{:choke, true}])
    {:ok, pid2} = generate_peer(session, incoming: [{:choke, false}])
    {:ok, pid3} = generate_peer(session, incoming: [{:choke, true}])

    result = Swarm.Query.choking_us(session)

    assert pid1 in result
    refute pid2 in result
    assert pid3 in result
  end

  test "query for peers we are choking" do
    session = generate_session()
    {:ok, pid1} = generate_peer(session, outgoing: [{:choke, true}])
    {:ok, pid2} = generate_peer(session, outgoing: [{:choke, false}])
    {:ok, pid3} = generate_peer(session, outgoing: [{:choke, true}])

    result = Swarm.Query.choked_peers(session)

    assert pid1 in result
    refute pid2 in result
    assert pid3 in result
  end
end
