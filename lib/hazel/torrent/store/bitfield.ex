defmodule Hazel.Torrent.Store.BitField do
  @moduledoc """
  An agent that keep track of which pieces are available in the file
  (written and verified)
  """

  @type peer_id :: binary
  @type info_hash :: binary
  @type on_start ::
    {:ok, pid} |
    {:error, {:already_started, pid} | term}

  @doc """
  Start and link a process containing a bit field
  """
  @spec start_link(peer_id, info_hash, Map.t) :: on_start
  def start_link(peer_id, info_hash, opts) do

    Agent.start_link(initial_value(info_hash, opts), name: via_name(peer_id, info_hash))
  end

  defp initial_value(info_hash, opts) do
    size = bitfield_size(opts[:length], opts[:piece_length])
    fn -> BitFieldSet.new!(<<>>, size, info_hash) end
  end

  defp bitfield_size(length, piece_length) do
    div(length, piece_length) + (if rem(length, piece_length) == 0, do: 0, else: 1)
  end

  defp via_name(peer_id, info_hash), do: {:via, :gproc, bitfield_name(peer_id, info_hash)}
  defp bitfield_name(peer_id, info_hash), do: {:n, :l, {__MODULE__, peer_id, info_hash}}

  @doc """
  Indicate that we have received the `piece` for the given `info_hash`.
  """
  @spec have(peer_id, info_hash, non_neg_integer) :: :ok
  def have(peer_id, info_hash, piece) do
    Agent.update(via_name(peer_id, info_hash), BitFieldSet, :set, [piece])
  end

  @doc """
  Indicate whether we have the given `piece` for the `info_hash`
  """
  @spec has?(peer_id, info_hash, non_neg_integer) :: boolean
  def has?(peer_id, info_hash, piece) do
    Agent.get(via_name(peer_id, info_hash), BitFieldSet, :member?, [piece])
  end

  @doc """
  Returns true if we have all the pieces for the given `info_hash`
  """
  @spec has_all?(peer_id, info_hash) :: boolean
  def has_all?(peer_id, info_hash) do
    Agent.get(via_name(peer_id, info_hash), BitFieldSet, :has_all?, [])
  end

  @doc """
  Return a set of the available pieces for the given `info_hash`
  """
  @spec available(peer_id, info_hash) :: MapSet.t
  def available(peer_id, info_hash) do
    Agent.get(via_name(peer_id, info_hash), &(&1.pieces))
  end
end
