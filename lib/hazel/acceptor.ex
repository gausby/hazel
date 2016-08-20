defmodule Hazel.Acceptor do
  @moduledoc false

  use Supervisor

  def start_link(local_id, opts) do
    Supervisor.start_link(__MODULE__, {local_id, opts}, name: via_name(local_id))
  end

  defp via_name(pid) when is_pid(pid), do: pid
  defp via_name(local_id), do: {:via, :gproc, reg_name(local_id)}
  defp reg_name(local_id), do: {:n, :l, {__MODULE__, local_id}}

  def init({local_id, opts}) do
    ranch_listener =
      :ranch.child_spec(
        {__MODULE__, local_id}, 10, :ranch_tcp,
        Keyword.take(opts, [:port]),
        Hazel.Acceptor.Handler, local_id)

    children = [
      supervisor(Hazel.Acceptor.Blacklist, [local_id]),
      ranch_listener
    ]
    supervise(children, strategy: :one_for_one)
  end
end
