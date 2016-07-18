defmodule Hazel.Torrent.Store.Controller do
  @moduledoc false
  use GenServer

  # Client API
  def start_link(peer_id, info_hash, opts) do
    GenServer.start_link(__MODULE__, opts, name: via_name({peer_id, info_hash}))
  end

  defp via_name(session), do: {:via, :gproc, controller_name(session)}
  defp controller_name({peer_id, info_hash}), do: {:n, :l, {__MODULE__, peer_id, info_hash}}

  # Server callbacks
  def init(state) do
    {:ok, state}
  end
end
