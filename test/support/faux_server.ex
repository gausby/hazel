defmodule Hazel.TestHelpers.FauxServer do
  use GenServer

  # Client API
  def start_link(peer_id, info_hash, opts \\ []) do
    opts = Keyword.merge(opts, pid: self, info_hash: info_hash, peer_id: peer_id)
    case Keyword.pop(opts, :mod) do
      {nil, _} ->
        raise ArgumentError, message: "please provide a mod name in the options"

      {mod, opts} ->
        GenServer.start_link(__MODULE__, opts, name: via_name({peer_id, info_hash}, mod))
    end
  end

  defp via_name(session, mod), do: {:via, :gproc, faux_name(session, mod)}
  defp faux_name({peer_id, info_hash}, mod), do: {:n, :l, {mod, peer_id, info_hash}}

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
    reply =
      if is_function(state[:cb][command]) do
        apply(state[:cb][command], args ++ [state])
      end
    {:reply, reply, state}
  end
end
