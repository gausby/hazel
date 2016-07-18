defmodule Hazel.Supervisor do
  @moduledoc false

  use Supervisor

  @type peer_id :: binary
  @type options :: [option]
  @type option ::
    {:port, integer}

  @spec start_link(peer_id, options) ::
    {:ok, pid} |
    :ignore |
    {:error, {:already_started, pid} | {:shutdown, term} | term}
  def start_link(<<peer_id::binary-size(20)>>, opts \\ []) do
    Supervisor.start_link(__MODULE__, {peer_id, opts}, name: via_name(peer_id))
  end

  defp via_name(peer_id), do: {:via, :gproc, supervisor_name(peer_id)}
  defp supervisor_name(peer_id), do: {:n, :l, {__MODULE__, peer_id}}

  def init({peer_id, _opts}) do
    children = [
      # acceptor
      # resource manager
      worker(Hazel.Blacklist, [peer_id]),
      supervisor(Hazel.PeerDiscovery, [peer_id]),
      supervisor(Hazel.Torrent, [peer_id])
    ]
    supervise(children, strategy: :one_for_one)
  end
end
