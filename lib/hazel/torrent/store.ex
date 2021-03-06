defmodule Hazel.Torrent.Store do
  @moduledoc """
  Random access read and write to a file descriptor.
  """

  alias __MODULE__

  use Supervisor

  def start_link(local_id, info_hash, opts) do
    Supervisor.start_link(__MODULE__, {local_id, info_hash, opts}, name: via_name({local_id, info_hash}))
  end

  defp via_name(pid) when is_pid(pid), do: pid
  defp via_name(session), do: {:via, :gproc, reg_name(session)}
  defp reg_name({local_id, info_hash}), do: {:n, :l, {__MODULE__, local_id, info_hash}}

  def init({local_id, info_hash, opts}) do
    children = [
      worker(Store.BitField, [local_id, info_hash, Keyword.take(opts, [:length, :piece_length])]),
      worker(Store.File, [local_id, info_hash, Keyword.take(opts, [:name, :pieces, :length, :piece_length])]),
      supervisor(Store.Piece.Supervisor, [local_id, info_hash, Keyword.take(opts, [:length, :piece_length])])
    ]

    supervise(children, strategy: :one_for_all)
  end

  defdelegate get_piece(session, piece_index), to: Store.Piece.Supervisor

  defdelegate write_chunk(session, piece_index, offset, data), to: Store.Piece

  defdelegate get_chunk(session, piece_index, offset, length), to: Store.File

  defdelegate available(session), to: Store.BitField

  defdelegate bit_field_size(session), to: Store.BitField

  defdelegate has?(session, piece_index), to: Store.BitField
end
