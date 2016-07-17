defmodule Hazel.Blacklist do
  @moduledoc false

  def start_link(<<peer_id::binary-size(20)>>) do
    Agent.start_link(fn -> MapSet.new() end, name: via_name(peer_id))
  end

  defp via_name(peer_id), do: {:via, :gproc, blacklist_name(peer_id)}
  defp blacklist_name(peer_id), do: {:n, :l, {__MODULE__, peer_id}}

  def member?(peer_id, peer) do
    Agent.get(via_name(peer_id), MapSet, :member?, [peer])
  end

  def put(peer_id, peer) do
    Agent.update(via_name(peer_id), MapSet, :put, [peer])
  end
end
