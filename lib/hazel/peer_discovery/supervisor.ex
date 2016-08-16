defmodule Hazel.PeerDiscovery.Supervisor do
  @moduledoc false

  @type local_id :: binary
  @type peer_id :: binary
  @type info_hash :: binary
  @type session :: local_id

  @spec add_peer(session, {peer_id, :inet.addr}, info_hash) :: :ok
  def add_peer(session, {peer_id, addr}, info_hash) do
    nil # todo
  end

  use Supervisor

  def start_link(session) do
    Supervisor.start_link(__MODULE__, session, name: via_name(session))
  end

  defp via_name(session), do: {:via, :gproc, reg_name(session)}
  def reg_name(local_id), do: {:n, :l, {__MODULE__, local_id}}

  @spec add_service(session, mod :: atom, args :: Keyword.t) :: :ok
  def add_service(session, mod, args) do

  end

  def init(local_id) do
    children = [
      worker(Hazel.PeerDiscovery.Service, [local_id])
    ]
    supervise(children, strategy: :simple_one_for_one)
  end
end

defmodule Hazel.PeerDiscovery.Service do
  @moduledoc false
  use GenServer

  # Client API
  def start_link(default) do
    GenServer.start_link(__MODULE__, default)
  end

  # Server callbacks
  def init(state) do
    {:ok, state}
  end
end
