defmodule Hazel.TestHelpers do
  @moduledoc false

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
