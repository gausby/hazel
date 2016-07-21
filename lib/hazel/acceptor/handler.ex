defmodule Hazel.Acceptor.Handler do
  @behaviour :ranch_protocol

  alias Hazel.{PeerWire, Torrent}

  def start_link(ref, socket, transport, opts) do
    :proc_lib.start_link(__MODULE__, :init, [ref, socket, transport, opts])
  end

  def init(ref, socket, transport, peer_id) do
    :ok = :proc_lib.init_ack({:ok, self})
    :ok = :ranch.accept_ack(ref)

    with :ok <- not_on_the_blacklist(peer_id, socket),
         {:ok, remote_id, info_hash} <- receive_handshake(socket, transport),
         {:ok, _} <- Torrent.where_is({peer_id, info_hash}),
         :ok <- PeerWire.complete_handshake(socket, transport, info_hash, peer_id) do
      # hand the socket over to the swarm
      :gen_server.enter_loop(__MODULE__, [], {remote_id, socket, transport})
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
      {:ok, _their_peer_id, _info_hash} = result ->
        result

      _ ->
        {:error, :malformed_handshake}
    end
  end

  defp not_on_the_blacklist(peer_id, socket) do
    {:ok, {ip, port}} = :inet.peername(socket)
    remote = "#{ip |> Tuple.to_list |> Enum.join(".")}:#{port}"

    if Hazel.Acceptor.Blacklist.member?(peer_id, remote),
      do: {:error, :peer_is_blacklisted},
      else: :ok
  end
end
