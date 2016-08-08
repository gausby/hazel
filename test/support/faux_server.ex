defmodule Hazel.TestHelpers.FauxServer do
  use GenServer

  # Client API
  def start_link(local_id, info_hash, opts \\ []) do
    opts = Keyword.merge(opts, pid: self, info_hash: info_hash, peer_id: local_id)
    case Keyword.pop(opts, :mod) do
      {nil, _} ->
        raise ArgumentError, message: "please provide a mod name in the options"

      {mod, opts} ->
        GenServer.start_link(__MODULE__, opts, name: via_name({local_id, info_hash}, mod))
    end
  end

  defp via_name(session, mod), do: {:via, :gproc, faux_name(session, mod)}
  defp faux_name({local_id, info_hash}, mod), do: {:n, :l, {mod, local_id, info_hash}}

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

defmodule Hazel.TestHelpers.FauxServerDeux do
  use GenServer

  # Client API
  def start_link(session, opts \\ []) do
    opts = Keyword.merge(opts, pid: self, session: session)
    GenServer.start_link(__MODULE__, opts, name: via_name(session))
  end

  defp via_name(session), do: {:via, :gproc, faux_name(session)}
  defp faux_name(session), do: {:n, :l, session}

  # Server callbacks
  def init(state), do: {:ok, state}

  def handle_cast(message, state) do
    [command|args] = Tuple.to_list(message)
    new_state =
      if is_function(state[:cb][command]) do
        case apply(state[:cb][command], args ++ [state]) do
          {:ok, state} when is_list(state) ->
            state

          :ok ->
            state

          _ ->
            raise ArgumentError,
              message: "should return `{:ok, state}`-tuple or just `:ok`"
        end
      else
        state
      end

    {:noreply, new_state}
  end

  def handle_call(message, _from, state) do
    # todo, fix handle_calls
    [command|args] = Tuple.to_list(message)
    {reply, new_state} =
      if is_function(state[:cb][command]) do
        apply(state[:cb][command], args ++ [state])
      end
    {:reply, reply, new_state}
  end
end
