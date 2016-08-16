defmodule Hazel.PeerDiscovery.Registry do
  @moduledoc false

  @type local_id :: binary
  @type session :: local_id

  def start_link(local_id) do
    Agent.start_link(fn -> Map.new() end, name: via_name(local_id))
  end

  defp via_name(pid) when is_pid(pid), do: pid
  defp via_name(session), do: {:via, :gproc, reg_name(session)}
  @doc false
  def reg_name(local_id), do: {:n, :l, {__MODULE__, local_id}}

  @type info_hash :: binary
  @type peer_id :: binary
  @type address :: {:inet.ip_address, :inet.port_number}
  @type peer :: {peer_id, address}
  @type peers :: [peer]

  @spec add_peer(session, info_hash, peer) :: :ok
  def add_peer(session, info_hash, peer) do
    Agent.update(via_name(session), fn registry ->
      Map.update(registry, info_hash, [peer], &([peer|&1]))
    end)
  end

  @spec get_peers(session, info_hash, num :: pos_integer) ::
    :unknown_info_hash | peers
  def get_peers(session, info_hash, n \\ 1) when n > 0 do
    Agent.get_and_update(via_name(session), fn registry ->
      if Map.has_key?(registry, info_hash) do
        Map.get_and_update(registry, info_hash, &(Enum.split(&1, n)))
      else
        {:unknown_info_hash, registry}
      end
    end)
  end

  @spec drop(session, info_hash) :: :ok
  def drop(session, info_hash) do
    Agent.update(session, Map, :delete, [info_hash])
  end
end
