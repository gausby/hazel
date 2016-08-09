defmodule Hazel.Torrent.Swarm.Peer.Controller do
  @moduledoc false

  use GenServer
  alias Hazel.Torrent.Swarm.Peer.{Receiver, Transmitter}
  alias Hazel.Torrent.Store

  # Client API
  def start_link(session, peer_id, opts) do
    session_id = {session, peer_id}
    opts = Keyword.merge(opts, session: session_id)
    GenServer.start_link(__MODULE__, opts, name: via_name(session_id))
  end

  defp via_name(pid) when is_pid(pid), do: pid
  defp via_name(session), do: {:via, :gproc, controller_name(session)}
  defp controller_name({{local_id, info_hash}, peer_id}), do: {:n, :l, {__MODULE__, local_id, info_hash, peer_id}}

  def handover_socket(session, {transport, socket} = connection) do
    case Receiver.where_is(session) do
      {:ok, pid} ->
        :ok = Transmitter.handover_socket(session, connection)
        :ok = transport.controlling_process(socket, pid)
        :ok = Receiver.handover_socket(pid, connection)

      {:error, _reason} = error ->
        error
    end
  end

  def request_tokens(session, something) do
    GenServer.cast(via_name(session), {:request_tokens, something})
  end

  def receive_message(session, message) do
    GenServer.cast(via_name(session), {:receive, message})
  end

  def handle_out(session, message) do
    GenServer.cast(via_name(session), {:transmit, message})
  end

  def status(session) do
    GenServer.call(via_name(session), :get_status)
  end

  defstruct [interesting?: false, peer_interested?: false,
             choking?: true, peer_choking?: true,
             bit_field: nil, session: nil]

  # Server callbacks
  def init(opts) do
    with {{local_id, info_hash}, _peer_id} = opts[:session],
         {:ok, bit_field_size} = Store.bit_field_size({local_id, info_hash}),
         {:ok, bit_field} = BitFieldSet.new(<<>>, bit_field_size, info_hash) do
      {:ok, %__MODULE__{session: opts[:session], bit_field: bit_field}}
    end
  end

  def handle_call(:get_status, _from, state) do
    {:reply, Map.drop(state, [:session]), state}
  end

  def handle_cast({:request_tokens, _pid}, state) do
    # ask tokens, get some stats about how long it took to consume
    # the given tokens
    {:noreply, state}
  end

  def handle_cast({:receive, message}, state) do
    case handle_message(Hazel.PeerWire.decode(message), state) do
      {:ok, state} ->
        {:noreply, state}

      {:error, _reason} ->
        # IO.inspect reason
        {:stop, :normal, state}
    end
  end

  def handle_cast({:transmit, message}, state) do
    # todo: "handle outgoing message"
    {:noreply, state}
  end

  defp handle_message(:awake, state) do
    {:ok, state}
  end

  defp handle_message({:choke, choking?}, state) do
    {:ok, %{state|peer_choking?: choking?}}
  end

  defp handle_message({:interest, interested?}, state) do
    {:ok, %{state|peer_interested?: interested?}}
  end

  defp handle_message({:bit_field, data}, %{bit_field: current} = state) do
    # make sure the size of the bit field match the expected length
    if BitFieldSet.empty?(current) do
      {{_local_id, info_hash}, _peer_id} = state.session
      case BitFieldSet.new(data, current.size, info_hash) do
        {:ok, bit_field} ->
          {:ok, %{state|bit_field: bit_field}}

        {:error, :out_of_bounds} ->
          {:error, :protocol_violation}
      end
    else
      # tried to redefine bit field after it was changed
      {:error, :protocol_violation}
    end
  end

  defp handle_message({:have, piece_index}, %{bit_field: bit_field} = state) do
    # update local bit field with this information
    {:ok, %{state|bit_field: BitFieldSet.set(bit_field, piece_index)}}
  end

  defp handle_message({:request, piece_index, offset, byte_length}, state) do
    # - Should only respond to this if we have the given piece_index
    # - Add this request to the transmitter queue
    IO.inspect {:request, piece_index, offset, byte_length}
    {:ok, state}
  end

  defp handle_message({:cancel, piece_index, offset, byte_length}, state) do
    # - Remove request from job queue in transmitter
    IO.inspect {:cancel, piece_index, offset, byte_length}
    {:ok, state}
  end

  defp handle_message({:piece, piece_index, offset, data}, %{session: {session, _}} = state) do
    # this call should probably be sync so we can kill the connection
    # if we are trying to write to something that doesn't exist
    :ok = Store.write_chunk(session, piece_index, offset, data)
    {:ok, state}
  end
end
