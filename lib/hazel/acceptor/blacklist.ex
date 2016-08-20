defmodule Hazel.Acceptor.Blacklist do
  @moduledoc false

  def start_link(<<local_id::binary-size(20)>>) do
    Agent.start_link(fn -> MapSet.new() end, name: via_name(local_id))
  end

  defp via_name(pid) when is_pid(pid), do: pid
  defp via_name(local_id), do: {:via, :gproc, blacklist_name(local_id)}
  defp blacklist_name(local_id), do: {:n, :l, {__MODULE__, local_id}}

  def member?(local_id, peer) do
    Agent.get(via_name(local_id), MapSet, :member?, [peer])
  end

  def put(local_id, peer) do
    Agent.update(via_name(local_id), MapSet, :put, [peer])
  end
end
