defmodule Hazel.PeerDiscovery.RegistryTest do
  use ExUnit.Case, async: true

  alias Hazel.PeerDiscovery.Registry

  test "start a registry" do
    session = generate_session()
    assert {:ok, _pid} = generate_registry(session)
  end

  test "add a peer to the registry" do
    session = generate_session()
    info_hash = :crypto.strong_rand_bytes(20)
    {:ok, pid} = generate_registry(session)

    assert :ok = Registry.add_peer(pid, info_hash, generate_peer())
  end

  test "add a peers to the registry and get them" do
    session = generate_session()
    info_hash = :crypto.strong_rand_bytes(20)
    peer_num = 3
    {:ok, pid} = generate_registry(session)

    peers = add_n_peers(session, info_hash, peer_num)

    assert ^peers = Enum.reverse(Registry.get_peers(pid, info_hash, peer_num))
  end

  test "getting from an unknown info_hash" do
    session = generate_session()
    info_hash = :crypto.strong_rand_bytes(20)
    info_hash2 = :crypto.strong_rand_bytes(20)
    peer_num = 2
    {:ok, pid} = generate_registry(session)

    add_n_peers(session, info_hash, peer_num)

    assert :unknown_info_hash = Registry.get_peers(pid, info_hash2, peer_num)
  end

  test "dropping peers for a given info_hash" do
    session = generate_session()
    info_hash = :crypto.strong_rand_bytes(20)
    peer_num = 2
    {:ok, pid} = generate_registry(session)

    peers = add_n_peers(session, info_hash, peer_num)
    assert ^peers = Enum.reverse(Registry.get_peers(pid, info_hash, peer_num))
    :ok = Registry.drop(pid, info_hash)
    assert :unknown_info_hash = Registry.get_peers(pid, info_hash, peer_num)
  end

  test "dropping peers for an unknown info_hash" do
    session = generate_session()
    info_hash = :crypto.strong_rand_bytes(20)
    {:ok, pid} = generate_registry(session)
    assert :ok = Registry.drop(pid, info_hash)
  end

  defp generate_session() do
    Hazel.generate_peer_id()
  end

  defp generate_registry(session) do
    {:ok, _pid} = Registry.start_link(session)
  end

  defp generate_peer() do
    <<a, b, c, d>> = :crypto.strong_rand_bytes(4)
    {{a, b, c, d}, :rand.uniform(65536) + 1}
  end

  defp add_n_peers(session, info_hash, n) do
    for _ <- 1..n do
      peer = generate_peer()
      :ok = Registry.add_peer(session, info_hash, peer)
      peer
    end
  end
end
