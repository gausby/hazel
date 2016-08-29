defmodule Hazel.Torrent.ControllerTest do
  use ExUnit.Case, async: true

  import Hazel.TestHelpers, only: [generate_peer_id: 0]

  alias Hazel.Torrent
  alias Hazel.Torrent.Swarm.Peer

  alias Hazel.TestHelpers.FauxServer

  test "broadcast have messages to all peers in the session" do
    session = generate_session()
    {:ok, _pid} = create_torrent_controller(session)
    {:ok, result} = add_n_peers_to_swarm(session, 5)
    :ok = Torrent.Controller.broadcast_piece(session, 5)

    # should be send to all peers (five) and no more ...
    for _ <- 1..(length result), do: assert_receive {:have, 5}
    refute_receive {:have, 5}
  end

  defp generate_session() do
    local_id = generate_peer_id()
    info_hash = :crypto.strong_rand_bytes(20)
    {local_id, info_hash}
  end

  defp create_torrent_controller({local_id, info_hash}) do
    Hazel.Torrent.Controller.start_link(local_id, info_hash)
  end

  defp peer_controller_reg_name({{local_id, info_hash}, peer_id}) do
    {Peer.Controller, local_id, info_hash, peer_id}
  end

  defp add_peer_to_swarm(session) do
    peer_id = generate_peer_id()
    {:ok, _pid} =
      FauxServer.start_link(
        peer_controller_reg_name({session, peer_id}),
        [cb: [
            broadcast:
            fn message, state ->
              send state[:pid], message
              :ok
            end]])
    {:ok, {session, peer_id}}
  end

  defp add_n_peers_to_swarm(session, n) do
    result =
      for _ <- 1..n do
        {:ok, peer_session} = add_peer_to_swarm(session)
        peer_session
      end
    {:ok, result}
  end
end
