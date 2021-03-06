defmodule Hazel.PeerWire do
  @protocol "BitTorrent Protocol"
  @protocol_length byte_size(@protocol)

  defp protocol_header(capabilities) do
    [@protocol_length, @protocol, capabilities]
  end

  @local_capabilities <<0, 0, 0, 0, 0, 0, 0, 0>>
  def receive_handshake(socket, transport) do
    # send as much as possible (the header) to the remote
    initial_handshake = protocol_header(@local_capabilities)
    :ok = transport.send(socket, initial_handshake)

    # await handshake from remote
    case transport.recv(socket, 68, 5000) do
      {:ok, <<@protocol_length, @protocol, _capabilities::binary-size(8),
              info_hash::binary-size(20), peer_id::binary-size(20)>>} ->
        {:ok, peer_id, info_hash, fn
          local_id, ^info_hash ->
            transport.send(socket, [info_hash, local_id])

          _, _ ->
            {:error, :info_hash_mishmash}
        end}

      {:ok, _} ->
        {:error, :malformed_handshake}
    end
  end

  @type piece_index :: non_neg_integer
  @type byte_length :: non_neg_integer
  @type offset :: non_neg_integer

  @type message ::
    :keep_alive | {:choke, boolean} | {:interest, boolean} |
    {:bit_field, binary} | {:have, non_neg_integer} |
    {:request | :cancel, piece_index, offset, byte_length} |
    {:piece, piece_index, offset, block :: binary}

  @choke 0
  @unchoke 1
  @interested 2
  @not_interested 3
  @have 4
  @bitfield 5
  @request 6
  @piece 7
  @cancel 8

  @spec decode(binary) :: message
  def decode(<<0::big-size(32)>>), do: :keep_alive
  def decode(<<1::big-size(32), @choke>>), do: {:choke, true}
  def decode(<<1::big-size(32), @unchoke>>), do: {:choke, false}
  def decode(<<1::big-size(32), @interested>>), do: {:interest, true}
  def decode(<<1::big-size(32), @not_interested>>), do: {:interest, false}
  def decode(<<5::big-size(32), @have, piece_index::big-size(32)>>), do: {:have, piece_index}
  def decode(<<13::big-size(32), @request,
               index::big-size(32), offset::big-size(32), bytes::big-size(32)>>) do
    {:request, index, offset, bytes}
  end
  def decode(<<13::big-size(32), @cancel,
               index::big-size(32), offset::big-size(32), bytes::big-size(32)>>) do
    {:cancel, index, offset, bytes}
  end
  def decode(<<_::big-size(32), @bitfield, bit_field::binary>>) do
    {:bit_field, bit_field}
  end
  def decode(<<_::big-size(32), @piece,
               index::big-size(32), offset::big-size(32), block::binary>>) do
    {:piece, index, offset, block}
  end

  @spec encode(message) :: binary
  def encode(:keep_alive), do: <<0, 0, 0, 0>>
  def encode({:choke, status}) do
    status
    |> if(do: <<@choke>>, else: <<@unchoke>>)
    |> with_message_length()
  end
  def encode({:interest, status}) do
    status
    |> if(do: <<@interested>>, else: <<@not_interested>>)
    |> with_message_length()
  end
  def encode({:have, piece_index}) do
    <<@have, piece_index::big-size(32)>>
    |> with_message_length()
  end
  def encode({:bit_field, bit_field}) do
    <<@bitfield, bit_field::binary>>
    |> with_message_length()
  end
  def encode({:request, index, offset, byte_length}) do
    <<@request, index::big-size(32), offset::big-size(32), byte_length::big-size(32)>>
    |> with_message_length()
  end
  def encode({:piece, index, offset, block}) do
    <<@piece, index::big-size(32), offset::big-size(32), block::binary>>
    |> with_message_length()
  end
  def encode({:cancel, index, offset, byte_length}) do
    <<@cancel, index::big-size(32), offset::big-size(32), byte_length::big-size(32)>>
    |> with_message_length()
  end

  defp with_message_length(data) do
    IO.iodata_to_binary([<<(byte_size(data))::big-size(32)>>, data])
  end
end
