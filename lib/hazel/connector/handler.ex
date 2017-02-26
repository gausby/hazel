defmodule Hazel.Connector.Handler do
  @behaviour :ranch_protocol

  alias Hazel.{PeerWire, Torrent, Torrent.Swarm}

  def start_link(ref, socket, transport, opts) do
    :proc_lib.start_link(__MODULE__, :init, [ref, socket, transport, opts])
  end

  def init(ref, socket, transport, local_id) do
    :ok = :proc_lib.init_ack({:ok, self()})
    :ok = :ranch.accept_ack(ref)

    with :ok <- not_on_the_blacklist(local_id, socket),
         {:ok, peer_id, info_hash, complete_handshake} <- receive_handshake(socket, transport),
         {:ok, _} <- Torrent.where_is({local_id, info_hash}),
         :ok <- complete_handshake.(local_id, info_hash) do
      # add peer to the swarm and hand over the socket and transport
      session = {local_id, info_hash}
      {:ok, _pid} = Torrent.add_peer(session, peer_id)
      :ok = Swarm.Peer.handover_socket({session, peer_id}, {transport, socket})
    else
      {:error, :peer_is_blacklisted} ->
        :ignore

      {:error, :unknown_session} ->
        :ignore

      {:error, :malformed_handshake} ->
        :ignore

      {:error, :info_hash_mishmash} ->
        :ignore
    end
  end

  defp receive_handshake(socket, transport) do
    case PeerWire.receive_handshake(socket, transport) do
      {:ok, _peer_id, _info_hash, _complete_handshake} = result ->
        result

      _ ->
        {:error, :malformed_handshake}
    end
  end

  defp not_on_the_blacklist(local_id, socket) do
    {:ok, remote} = :inet.peername(socket)

    if Hazel.Connector.Blacklist.member?(local_id, remote),
      do: {:error, :peer_is_blacklisted},
      else: :ok
  end
end
