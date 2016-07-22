defmodule Hazel.Torrent.Controller do
  @moduledoc false
  use GenServer

  @type local_id :: binary
  @type info_hash :: binary
  @type session :: {local_id, info_hash}
  @type piece_index :: non_neg_integer

  # Client API
  def start_link(local_id, info_hash, opts) do
    GenServer.start_link(__MODULE__, opts, via_name: via_name({local_id, info_hash}))
  end

  defp via_name(session), do: {:via, :gproc, controller_name(session)}
  defp controller_name({local_id, info_hash}), do: {:n, :l, {__MODULE__, local_id, info_hash}}

  @spec request_peer(session, piece_index) :: :ok
  def request_peer(session, piece_index) do
    GenServer.cast(via_name(session), {:request_peer, piece_index})
  end

  @spec broadcast_piece(session, piece_index) :: :ok
  def broadcast_piece(session, piece_index) do
    GenServer.cast(via_name(session), {:broadcast_piece, piece_index})
  end

  # Server callbacks
  def init(state) do
    {:ok, state}
  end
end
