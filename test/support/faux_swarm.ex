defmodule Hazel.Torrent.SwarmFaux do
  use GenServer

  # Client API
  def start_link(peer_id, info_hash, opts \\ []) do
    opts = Keyword.merge(opts, pid: self, info_hash: info_hash, peer_id: peer_id)
    GenServer.start_link(__MODULE__, opts, name: via_name(peer_id, info_hash))
  end

  defp via_name(peer_id, info_hash), do: {:via, :gproc, swarm_name(peer_id, info_hash)}
  defp swarm_name(peer_id, info_hash), do: {:n, :l, {Hazel.Torrent.Swarm, peer_id, info_hash}}

  # Server callbacks
  def init(state) do
    {:ok, state}
  end

  def handle_cast(message, state) do
    [command|args] = Tuple.to_list(message)
    if is_function(state[:cb][command]) do
      apply(state[:cb][command], args ++ [state])
    end
    {:noreply, state}
  end

  def handle_call(message, _from, state) do
    [command|args] = Tuple.to_list(message)
    if is_function(state[:cb][command]) do
      apply(state[:cb][command], args ++ [state])
    end
    {:reply, :ok, state}
  end
end
