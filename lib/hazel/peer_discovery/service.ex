defmodule Hazel.PeerDiscovery.Service do
  @moduledoc false

  @doc false
  defmacro __using__(_opts) do
    quote do
      @behaviour Hazel.PeerDiscovery.Service

      @type local_id :: binary
      @type source :: binary
      @type session :: {local_id, source}

      defp via_name(pid) when is_pid(pid), do: pid
      defp via_name(session), do: {:via, :gproc, reg_name(session)}
      @spec reg_name(session) ::
        {:n, :l, {Hazel.PeerDiscovery.Service, local_id, atom, source}}
      def reg_name({local_id, source}) when is_binary(source) do
        {:n, :l, {unquote(__MODULE__), local_id, __MODULE__, source}}
      end
    end
  end

  @type local_id :: binary
  @type source :: binary
  @type session :: {local_id, source}
  @type opts :: Keyword.t

  @callback start_link(session, opts) :: term
end
