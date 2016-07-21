defmodule Hazel.Torrent.Swarm do
  @moduledoc false

  use GenServer

  @type peer_id :: binary
  @type info_hash :: binary
  @type session :: {peer_id, info_hash}

  # Client API
  def start_link(peer_id, info_hash, opts) do
    GenServer.start_link(__MODULE__, opts, name: via_name({peer_id, info_hash}))
  end

  defp via_name(session), do: {:via, :gproc, swarm_name(session)}
  defp swarm_name({peer_id, info_hash}), do: {:n, :l, {__MODULE__, peer_id, info_hash}}

  # Server callbacks
  def init(state) do
    {:ok, state}
  end
end
