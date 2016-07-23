defmodule Hazel.Torrent.Swarm.Peer.ReceiverTest do
  use ExUnit.Case

  alias Hazel.Torrent.Swarm.Peer.Receiver

  defp start_receiver() do
    local_id = Hazel.generate_peer_id()
    peer_id = Hazel.generate_peer_id()
    info_hash = :crypto.strong_rand_bytes(20)

    Receiver.start_link({local_id, info_hash}, peer_id)
  end

  defp create_transport_and_socket(transport \\ :gen_tcp) do
    {:ok, socket} = transport.listen(0, [])
    {transport, socket}
  end

  test "starting a receiver" do
    {:ok, pid} = start_receiver()
    assert is_pid(pid)
  end

  test "receiving a transport and a socket" do
    {:ok, receiver_pid} = start_receiver()
    {transport, receiver_socket} = create_transport_and_socket()

    assert :ok = Receiver.handover_socket(receiver_pid, {transport, receiver_socket})
  end
end
