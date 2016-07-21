defmodule Hazel.PeerWire do
  @protocol "BitTorrent Protocol"
  @protocol_length byte_size(@protocol)

  @local_capabilities <<0, 0, 0, 0, 0, 0, 0, 0>>

  defp protocol_header(capabilities) do
    [@protocol_length, @protocol, capabilities]
  end

  def receive_handshake(socket, transport) do
    # send as much as possible (the header) to the remote
    initial_handshake = protocol_header(@local_capabilities)
    :ok = transport.send(socket, initial_handshake)

    # await handshake from remote
    case transport.recv(socket, 68, 5000) do
      {:ok, <<@protocol_length, @protocol, _capabilities::binary-size(8),
              info_hash::binary-size(20), peer_id::binary-size(20)>>} ->
        {:ok, peer_id, info_hash}
    end
  end

  def complete_handshake(socket, transport, info_hash, peer_id) do
    transport.send(socket, [info_hash, peer_id])
  end
end
