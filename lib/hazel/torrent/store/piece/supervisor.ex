defmodule Hazel.Torrent.Store.Piece.Supervisor do
  use Supervisor

  alias Hazel.Torrent.Store

  def start_link(local_id, info_hash, opts) do
    Supervisor.start_link(__MODULE__, {local_id, info_hash, opts}, name: via_name({local_id, info_hash}))
  end

  defp via_name(pid) when is_pid(pid), do: pid
  defp via_name(session), do: {:via, :gproc, reg_name(session)}
  defp reg_name({local_id, info_hash}), do: {:n, :l, {__MODULE__, local_id, info_hash}}

  def get_piece(session, piece_index) do
    with {:ok, pid} <- where_is(session),
         :ok <- piece_not_available?(session, piece_index) do
      Supervisor.start_child(pid, [piece_index])
    end
  end

  def init({local_id, info_hash, opts}) do
    piece_length = opts[:piece_length]
    number_of_pieces = calc_number_of_pieces(opts[:length], piece_length)
    last_piece_length = calc_last_piece_length(opts[:length], piece_length)

    children = [
      worker(Store.Piece,
        [local_id, info_hash, [number_of_pieces: number_of_pieces,
                               piece_length: piece_length,
                               last_piece_length: last_piece_length,
                               chunk_size: opts[:chunk_size]]])
    ]

    supervise(children, strategy: :simple_one_for_one)
  end

  defp calc_last_piece_length(total_length, piece_length) do
    case rem(total_length, piece_length) do
      0 ->
        piece_length

      remaining ->
        remaining
    end
  end

  defp calc_number_of_pieces(length, piece_length) do
    div(length, piece_length) + (if rem(length, piece_length) == 0, do: 0, else: 1)
  end

  defp where_is(session) do
    case :gproc.where(reg_name(session)) do
      pid when is_pid(pid) ->
        {:ok, pid}

      :undefined ->
        {:error, :unknown_info_hash}
    end
  end

  defp piece_not_available?(session, piece_index) do
    if Store.has?(session, piece_index),
      do: {:error, :requested_piece_is_already_available},
      else: :ok
  end
end
