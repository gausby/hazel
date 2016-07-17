defmodule Hazel.Torrent.Store.File do
  @moduledoc """

  """
  use GenServer

  alias __MODULE__, as: State

  @type peer_id :: binary
  @type info_hash :: binary
  @type piece_index :: non_neg_integer
  @type offset :: non_neg_integer
  @type chunk_length :: non_neg_integer

  @type io_device :: :file.io_device
  @type nodata :: {:error, term} | :eof

  @type t :: %__MODULE__{source: Path.t,
                         hashes: [{non_neg_integer, binary}],
                         fd: io_device,
                         piece_length: non_neg_integer,
                         last_piece_length: non_neg_integer,
                         last_piece_index: non_neg_integer}
  defstruct [source: "", hashes: [], fd: nil,
             piece_length: 0, last_piece_length: 0,
             last_piece_index: 0]

  # Client API
  def start_link(peer_id, info_hash, opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: via_name(peer_id, info_hash))
  end

  defp via_name(peer_id, info_hash), do: {:via, :gproc, file_name(peer_id, info_hash)}
  defp file_name(peer_id, info_hash), do: {:n, :l, {__MODULE__, peer_id, info_hash}}

  @spec write_chunk(peer_id, info_hash, piece_index, offset, binary) ::
    {:error, :out_of_bounds} | {:error, :out_of_piece_bounds} | {:error, term} |
    :ok
  def write_chunk(peer_id, info_hash, piece_index, offset, content) do
    GenServer.call(via_name(peer_id, info_hash), {:write_chunk, piece_index, offset, content})
  end

  @spec get_chunk(peer_id, info_hash, piece_index, offset, chunk_length) ::
    {:error, :out_of_piece_bounds} | {:error, :out_of_bounds} |
    {:ok, iodata | nodata}
  def get_chunk(peer_id, info_hash, piece_index, offset, chunk_length) do
    GenServer.call(via_name(peer_id, info_hash), {:get_chunk, piece_index, offset, chunk_length})
  end

  @spec get_piece(peer_id, info_hash, piece_index) ::
    {:error, :out_of_bounds} | {:error, :out_of_piece_bounds} |
    {:ok, iodata | nodata}
  def get_piece(peer_id, info_hash, piece_index) do
    GenServer.call(via_name(peer_id, info_hash), {:get_piece, piece_index})
  end

  @spec validate_piece(peer_id, info_hash, piece_index ) :: boolean
  def validate_piece(peer_id, info_hash, piece_index) do
    GenServer.call(via_name(peer_id, info_hash), {:validate_piece, piece_index})
  end

  # Server callbacks
  @doc false
  def init(opts) do
    with {:ok, pieces} <- split_into_indexed_pieces(opts[:pieces]),
         {:ok, fd} <- open_file(opts[:name]),
         hashes = :ets.new(:hashes, []),
         true = :ets.insert(hashes, pieces) do
      {:ok,
       %State{source: opts[:name],
              fd: fd,
              hashes: hashes,
              piece_length: opts[:piece_length],
              last_piece_length: calculate_last_piece_length(opts[:length], opts[:piece_length]),
              last_piece_index: length(pieces) - 1}}
    else
      {:error, reason} ->
        {:stop, reason}
    end
  end

  defp open_file(:ram), do: do_open_file("", [:ram])
  defp open_file(file_name) when is_binary(file_name), do: do_open_file(file_name)

  defp do_open_file(file_name, extra_opts \\ []) do
    File.open(file_name, [:read, :write] ++ extra_opts)
  end

  defp calculate_last_piece_length(total_length, piece_length) do
    case rem(total_length, piece_length) do
      0 ->
        piece_length

      remaining ->
        remaining
    end
  end

  defp split_into_indexed_pieces(pieces, index \\ 0, acc \\ [])
  defp split_into_indexed_pieces(<<>>, _index, acc) do
    {:ok, Enum.reverse(acc)}
  end
  defp split_into_indexed_pieces(<<piece::binary-size(20), pieces::binary>>, index, acc) do
    split_into_indexed_pieces(pieces, index + 1, [{index, piece}|acc])
  end
  defp split_into_indexed_pieces(_, _, _) do
    {:error, :malformed_pieces}
  end

  @doc false
  def handle_call({:write_chunk, index, offset, content}, _from,
        %State{piece_length: piece_length, last_piece_index: last_piece_index} = state)
  when index <= last_piece_index and byte_size(content) <= piece_length do
    out_of_piece_bounds? =
      offset + byte_size(content) > piece_length(index, state)

    result =
      unless out_of_piece_bounds? do
        byte_offset = (index * piece_length) + offset
        {:ok, ^byte_offset} = :file.position(state.fd, byte_offset)
        IO.binwrite(state.fd, content)
      else
        {:error, :out_of_piece_bounds}
      end

    {:reply, result, state}
  end
  def handle_call({:write_chunk, _, _, _}, _from, state) do
    {:reply, {:error, :out_of_bounds}, state}
  end

  @doc false
  def handle_call({:validate_piece, index}, _from, state) do
    case read_piece(index, state) do
      {:ok, piece_content} ->
        hash = :ets.lookup_element(state.hashes, index, 2)
        valid? = :crypto.hash(:sha, piece_content) == hash
        {:reply, valid?, state}

      _ ->
        # todo
        {:reply, false, state}
    end
  end

  @doc false
  def handle_call({:get_piece, index}, _from, %State{last_piece_index: last_piece_index} = state)
  when index <= last_piece_index do
    case read_piece(index, state) do
      {:ok, piece_content} ->
        {:reply, piece_content, state}

      error ->
        {:reply, error, state}
    end
  end
  def handle_call({:get_piece, _index}, _from, state) do
    {:reply, {:error, :out_of_bounds}, state}
  end

  @doc false
  def handle_call({:get_chunk, index, offset, length}, _from, state) do
    content = read_piece(index, offset, length, state)
    {:reply, content, state}
  end

  defp read_piece(index, %State{last_piece_index: last_piece_index} = state)
  when index <= last_piece_index do
    length = piece_length(index, state)
    read_piece(index, 0, length, state)
  end

  defp read_piece(index, offset, length, %State{last_piece_index: last_piece_index} = state)
  when index <= last_piece_index do
    # should probably check if the piece exist before moving the cursor
    out_of_piece_bounds? =
      offset + length > piece_length(index, state)

    unless out_of_piece_bounds? do
      byte_offset = (index * state.piece_length) + offset
      {:ok, ^byte_offset} = :file.position(state.fd, byte_offset)
      {:ok, IO.binread(state.fd, length)}
    else
      {:error, :out_of_piece_bounds}
    end
  end
  defp read_piece(_index, _offset, _length, _state) do
    {:error, :out_of_bounds}
  end

  defp piece_length(index, %State{last_piece_index: index, last_piece_length: length}) do
    length
  end
  defp piece_length(_index, %State{piece_length: length}) do
    length
  end
end
