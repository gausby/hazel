defmodule Hazel.Torrent.Swarm.Query do
  defstruct guards: [], params: %{}, result: [:'$1'], session: nil

  alias Hazel.Torrent.Swarm.Peer.Controller

  @type t :: %__MODULE__{}

  @type local_id :: binary
  @type info_hash :: binary
  @type session :: {local_id, info_hash}

  @spec interested_peers(session) :: [pid]
  def interested_peers(session) do
    session
    |> build_query()
    |> add_param(peer_interested?: true)
    |> search()
  end

  @spec choked_peers(session) :: [pid]
  def choked_peers(session) do
    session
    |> build_query()
    |> add_param(choking?: true)
    |> search()
  end

  @spec interesting_peers(session) :: [pid]
  def interesting_peers(session) do
    session
    |> build_query()
    |> add_param(interesting?: true)
    |> search()
  end

  @spec choking_us(session) :: [pid]
  def choking_us(session) do
    session
    |> build_query()
    |> add_param(peer_choking?: true)
    |> search()
  end

  defp build_query(session) do
    %__MODULE__{session: session}
  end

  defp add_param(%__MODULE__{params: params} = query, param) do
    updated_params =
      Enum.reduce(param, params, fn ({param, value}, acc) ->
        Map.put(acc, param, value)
      end)

    %{query|params: updated_params}
  end

  @spec search(query :: t) :: [pid]
  def search(opts) do
    key = Controller.reg_name({opts.session, :'_'})

    match_head = {key, :'$1', opts.params}
    query = [{match_head, opts.guards, opts.result}]

    :gproc.select(query)
  end
end
