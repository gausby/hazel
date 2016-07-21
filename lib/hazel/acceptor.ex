defmodule Hazel.Acceptor do
  @moduledoc false

  use Supervisor

  def start_link(peer_id, opts) do
    Supervisor.start_link(__MODULE__, {peer_id, opts}, name: via_name(peer_id))
  end

  defp via_name(peer_id), do: {:via, :gproc, acceptor_name(peer_id)}
  defp acceptor_name(peer_id), do: {:n, :l, {__MODULE__, peer_id}}

  def init({peer_id, opts}) do
    ranch_listener =
      :ranch.child_spec(
        {__MODULE__, peer_id}, 10, :ranch_tcp,
        Keyword.take(opts, [:port]),
        Hazel.Acceptor.Handler, peer_id)

    children = [
      supervisor(Hazel.Acceptor.Blacklist, [peer_id]),
      ranch_listener
    ]
    supervise(children, strategy: :one_for_one)
  end
end
