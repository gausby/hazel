defmodule Hazel.PeerDiscovery.Service do
  @moduledoc false

  @doc false
  defmacro __using__(_opts) do
    quote do
      @behaviour Hazel.PeerDiscovery.Service
    end
  end

  @type session :: binary
  @type opts :: Keyword.t

  @callback start_link(session, opts) :: term
end
