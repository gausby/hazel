defmodule Hazel.TestHelpers.FauxServer do
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
    [command|args] = Tuple.to_list(message)
    if is_function(state[:cb][command]) do
      case apply(state[:cb][command], args ++ [state]) do
        {:ok, reply, new_state} when is_list(new_state) ->
          {:reply, reply, new_state}

        {:ok, reply} ->
          {:reply, reply, state}

        _ ->
          raise ArgumentError,
            message: "should return a `{:ok, reply, state}`- or an {:ok, reply}-tuple"
      end
    end
  end
end
