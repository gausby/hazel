defmodule Hazel.PeerDiscovery.Services do
  @moduledoc false

  use Supervisor

  @type local_id :: binary
  @type session :: local_id

  def start_link(session) do
    Supervisor.start_link(__MODULE__, session, name: via_name(session))
  end

  defp via_name(session), do: {:via, :gproc, reg_name(session)}
  defp reg_name(local_id), do: {:n, :l, {__MODULE__, local_id}}

  @spec start_service(session, mod :: atom, args :: Keyword.t) :: :ok
  def start_service(session, mod, args \\ []) when is_atom(mod) do
    Supervisor.start_child(via_name(session), [mod, args])
  end

  defmodule Service do
    @moduledoc false
    @doc false
    def start_link(session, mod, opts \\ []),
      do: apply(mod, :start_link, [session|opts])
  end

  @doc false
  def init(local_id) do
    supervise(
      [worker(Service, [local_id])],
      strategy: :simple_one_for_one)
  end
end
