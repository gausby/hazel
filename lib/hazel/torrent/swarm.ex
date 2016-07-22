defmodule Hazel.Torrent.Swarm do
  @moduledoc false

  use Supervisor

  @type peer_id :: binary
  @type info_hash :: binary
  @type session :: {peer_id, info_hash}

  def start_link(peer_id, info_hash, opts) do
    Supervisor.start_link(__MODULE__, {peer_id, info_hash, opts}, name: via_name({peer_id, info_hash}))
  end

  defp via_name(session), do: {:via, :gproc, swarm_name(session)}
  defp swarm_name({peer_id, info_hash}), do: {:n, :l, {__MODULE__, peer_id, info_hash}}

  def init({peer_id, info_hash, _opts}) do
    children = [
      supervisor(Hazel.Torrent.Swarm.Peer, [peer_id, info_hash])
    ]
    supervise(children, strategy: :simple_one_for_one)
  end

  @type child :: pid | :undefined

  @doc """
  Add a peer to the swarm
  """
  @spec add_peer(session, binary) ::
    {:ok, child} |
    {:ok, child, info :: term} |
    {:error, {:already_started, child} | :already_present | term}
  def add_peer(session, peer_id) do
    Supervisor.start_child(via_name(session), [peer_id])
  end
end
