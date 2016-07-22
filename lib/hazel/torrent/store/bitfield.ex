defmodule Hazel.Torrent.Store.BitField do
  @moduledoc """
  An agent that keep track of which pieces are available in the file
  (written and verified)
  """

  @type local_id :: binary
  @type info_hash :: binary
  @type session :: {local_id, info_hash}
  @type on_start ::
    {:ok, pid} |
    {:error, {:already_started, pid} | term}

  @doc """
  Start and link a process containing a bit field
  """
  @spec start_link(local_id, info_hash, Map.t) :: on_start
  def start_link(local_id, info_hash, opts) do
    Agent.start_link(initial_value(info_hash, opts), name: via_name({local_id, info_hash}))
  end

  defp initial_value(info_hash, opts) do
    size = bitfield_size(opts[:length], opts[:piece_length])
    fn -> BitFieldSet.new!(<<>>, size, info_hash) end
  end

  defp bitfield_size(length, piece_length) do
    div(length, piece_length) + (if rem(length, piece_length) == 0, do: 0, else: 1)
  end

  defp via_name(session), do: {:via, :gproc, bitfield_name(session)}
  defp bitfield_name({local_id, info_hash}), do: {:n, :l, {__MODULE__, local_id, info_hash}}

  @doc """
  Indicate that we have received the `piece` for the given `info_hash`.
  """
  @spec have(session, non_neg_integer) :: :ok
  def have(session, piece) do
    Agent.update(via_name(session), BitFieldSet, :set, [piece])
  end

  @doc """
  Indicate whether we have the given `piece` for the `info_hash`
  """
  @spec has?(session, non_neg_integer) :: boolean
  def has?(session, piece) do
    Agent.get(via_name(session), BitFieldSet, :member?, [piece])
  end

  @doc """
  Returns true if we have all the pieces for the given `info_hash`
  """
  @spec has_all?(session) :: boolean
  def has_all?(session) do
    Agent.get(via_name(session), BitFieldSet, :has_all?, [])
  end

  @doc """
  Return a set of the available pieces for the given `info_hash`
  """
  @spec available(session) :: MapSet.t
  def available(session) do
    Agent.get(via_name(session), &(&1.pieces))
  end
end
