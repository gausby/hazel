defmodule Hazel.TestHelpers do
  @moduledoc false

  def generate_peer_id() do
    Hazel.generate_peer_id()
  end

  # Create an TCP acceptor and return its IP and port number
  def create_acceptor(local_id) do
    Hazel.Connector.start_link(local_id, [port: 0])
    :gproc.await(Hazel.Connector.reg_name(local_id))
    :ranch.get_addr({Hazel.Connector, local_id})
  end

  # Create a valid handshake
  def create_handshake(<<peer_id::binary-size(20)>>, <<info_hash::binary-size(20)>>, opts \\ []) do
    protocol = "BitTorrent Protocol"
    reserved_bytes = Keyword.get(opts, :reserved, <<0, 0, 0, 0, 0, 0, 0, 0>>)
    [byte_size(protocol), protocol, reserved_bytes, info_hash, peer_id]
  end

  def create_torrent_file(data, opts) when is_binary(data) do
    length = byte_size(data)
    pieces =
      data
      |> split_into_chunks(opts[:piece_length])
      |> Enum.map(&(:crypto.hash(:sha, &1)))
      |> IO.iodata_to_binary

    [pieces: pieces, length: length, piece_length: opts[:piece_length], name: :ram]
  end

  def encode_torrent_file(torrent_data) do
    info =
      torrent_data
      |> Keyword.put(:name, "test-torrent.tar") # random file name
      |> Enum.map(&({Atom.to_string(elem(&1, 0)), elem(&1, 1)}))
      |> Enum.into(%{})

    Bencode.encode!(%{info: info})
  end

  defp split_into_chunks(data, len, acc \\ [])
  defp split_into_chunks(<<>>, _, acc), do: Enum.reverse(acc)
  defp split_into_chunks(data, len, acc) when len <= byte_size(data) do
    <<chunk::binary-size(len), rest::binary>> = data
    split_into_chunks(rest, len, [chunk|acc])
  end
  defp split_into_chunks(data, len, acc) do
    split_into_chunks(<<>>, len, [data|acc])
  end
end
