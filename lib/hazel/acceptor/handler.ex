defmodule Hazel.Acceptor.Handler do
  @behaviour :ranch_protocol

  alias Hazel.{PeerWire, Torrent, Torrent.Swarm}

  def start_link(ref, socket, transport, opts) do
    :proc_lib.start_link(__MODULE__, :init, [ref, socket, transport, opts])
  end

  def init(ref, socket, transport, local_id) do
    :ok = :proc_lib.init_ack({:ok, self})
    :ok = :ranch.accept_ack(ref)

    with :ok <- not_on_the_blacklist(local_id, socket),
         {:ok, peer_id, info_hash} <- receive_handshake(socket, transport),
         {:ok, _} <- Torrent.where_is({local_id, info_hash}),
         :ok <- PeerWire.complete_handshake(socket, transport, info_hash, local_id) do
      # add peer to the swarm and hand over the socket and transport
      session = {local_id, info_hash}
      {:ok, pid} = Swarm.add_peer(session, peer_id)
      :ok = Swarm.Peer.handover_socket({session, peer_id}, {transport, socket})
    else
      {:error, :peer_is_blacklisted} ->
        :ignore

      {:error, :unknown_session} ->
        :ignore

      {:error, :malformed_handshake} ->
        :ignore
    end
  end

  defp receive_handshake(socket, transport) do
    case Hazel.PeerWire.receive_handshake(socket, transport) do
      {:ok, _peer_id, _info_hash} = result ->
        result

      _ ->
        {:error, :malformed_handshake}
    end
  end

  defp not_on_the_blacklist(local_id, socket) do
    {:ok, {ip, port}} = :inet.peername(socket)
    remote = "#{ip |> Tuple.to_list |> Enum.join(".")}:#{port}"

    if Hazel.Acceptor.Blacklist.member?(local_id, remote),
      do: {:error, :peer_is_blacklisted},
      else: :ok
  end
end
