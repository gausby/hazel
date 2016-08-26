defmodule Hazel.Torrent.Swarm.Peer.Controller do
  @moduledoc false

  use GenServer
  alias Hazel.Torrent.Swarm.Peer.{Receiver, Transmitter}
  alias Hazel.Torrent.Store

  @type local_id :: binary
  @type info_hash :: binary
  @type peer_id :: binary
  @type session :: {local_id, info_hash}

  # Client API
  def start_link(session, peer_id, opts \\ []) do
    session_id = {session, peer_id}
    opts = Keyword.merge(opts, session: session_id)
    GenServer.start_link(__MODULE__, opts, name: via_name(session_id))
  end

  defp via_name(pid) when is_pid(pid), do: pid
  defp via_name(session), do: {:via, :gproc, reg_name(session)}

  @doc false
  @spec reg_name({session, peer_id}) ::
    {:n, :l, {__MODULE__, local_id, info_hash, peer_id}}
  def reg_name({{local_id, info_hash}, peer_id}),
    do: {:n, :l, {__MODULE__, local_id, info_hash, peer_id}}

  @type connection :: {transport :: :gen_tcp, socket :: :gen_tcp.socket}
  @spec handover_socket(session, connection) ::
    :ok | {:error, term} | no_return
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

  def request_tokens(session, tokens) do
    GenServer.cast(via_name(session), {:request_tokens, tokens})
  end

  @spec broadcast(session, Hazel.PeerWire.message) :: :ok
  def broadcast(session, message) do
    GenServer.cast(via_name(session), {:broadcast, message})
  end

  @spec incoming(session, Hazel.PeerWire.message) :: :ok
  def incoming(session, message) do
    GenServer.cast(via_name(session), {:receive, message})
  end

  @spec outgoing(session, Hazel.PeerWire.message) :: :ok
  def outgoing(session, message) do
    GenServer.cast(via_name(session), {:transmit, message})
  end

  @spec status(session) :: t
  def status(session) do
    GenServer.call(via_name(session), :get_status)
  end

  @type t :: %__MODULE__{
    interesting?: boolean(), peer_interested?: boolean(),
    choking?: boolean(), peer_choking?: boolean(),
    bit_field: BitFieldSet.t | nil,
    session: {session, peer_id} | nil
  }
  defstruct [interesting?: false, peer_interested?: false,
             choking?: true, peer_choking?: true,
             bit_field: nil, session: nil]

  defp update_status(%__MODULE__{} = status) do
    true =
      status.session
      |> reg_name()
      |> :gproc.set_value(status)
    status
  end

  # Server callbacks
  def init(opts) do
    with {{local_id, info_hash}, _peer_id} = opts[:session],
         {:ok, bit_field_size} = Store.bit_field_size({local_id, info_hash}),
         {:ok, bit_field} = BitFieldSet.new(<<>>, bit_field_size, info_hash) do

      {:ok, update_status(%__MODULE__{session: opts[:session], bit_field: bit_field})}
    end
  end

  def handle_call(:get_status, _from, state) do
    {:reply, Map.drop(state, [:session]), state}
  end

  def handle_cast({:broadcast, message}, state) do
    case handle_broadcast(message, state) do
      {:ok, :no_change} ->
        {:noreply, state}

      {:ok, state} ->
        {:noreply, update_status(state)}

      {:error, _reason} ->
        # IO.inspect reason
        {:stop, :normal, state}
    end
  end

  def handle_cast({:request_tokens, _pid}, state) do
    # ask for tokens, get some stats about how long it took to consume
    # the given tokens
    {:noreply, state}
  end

  def handle_cast({:receive, message}, state) do
    case handle_in(message, state) do
      {:ok, :no_change} ->
        {:noreply, state}

      {:ok, state} ->
        {:noreply, update_status(state)}

      {:error, _reason} ->
        # IO.inspect reason
        {:stop, :normal, state}
    end
  end

  def handle_cast({:transmit, message}, state) do
    case handle_out(message, state) do
      {:ok, state} ->
        {:noreply, update_status(state)}

      {:error, _reason} ->
        # IO.inspect reason
        {:stop, :normal, state}
    end
  end

  #=Broadcast ========================================================
  # Triggered when the message is put into the transmitter queue.
  defp handle_broadcast({:have, _} = message, state) do
    :ok = Transmitter.prepend(state.session, message)
    {:ok, :no_change}
  end

  #=Outgoing =========================================================
  # Triggered when the transmitter has completed sending the message
  # to the remote. It would be safe to assume that they got the memo
  # when this is triggered.
  defp handle_out({:choke, choke?}, state) when is_boolean(choke?) do
    {:ok, %{state|choking?: choke?}}
  end

  defp handle_out({:interest, interest?}, state) when is_boolean(interest?) do
    {:ok, %{state|interesting?: interest?}}
  end

  defp handle_out(_, state) do
    {:ok, state}
  end

  #=Incoming =========================================================
  # Triggered when the receiver process has received a full message
  # from the remote.
  defp handle_in(:awake, _state) do
    {:ok, :no_change}
  end

  defp handle_in({:choke, choking?}, state) do
    {:ok, %{state|peer_choking?: choking?}}
  end

  defp handle_in({:interest, interested?}, state) do
    {:ok, %{state|peer_interested?: interested?}}
  end

  defp handle_in({:bit_field, data}, %{bit_field: current} = state) do
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

  defp handle_in({:have, piece_index}, %{bit_field: bit_field} = state) do
    # update local bit field with this information
    {:ok, %{state|bit_field: BitFieldSet.set(bit_field, piece_index)}}
  end

  defp handle_in({:request, piece_index, offset, byte_length}, _state) do
    # - Should only respond to this if we have the given piece_index
    # - Add this request to the transmitter queue
    IO.inspect {:request, piece_index, offset, byte_length}
    {:ok, :no_change}
  end

  defp handle_in({:cancel, piece_index, offset, byte_length}, _state) do
    # - Remove request from job queue in transmitter
    IO.inspect {:cancel, piece_index, offset, byte_length}
    {:ok, :no_change}
  end

  defp handle_in({:piece, piece_index, offset, data}, %{session: {session, _}}) do
    # this call should probably be sync so we can kill the connection
    # if we are trying to write to something that doesn't exist
    :ok = Store.write_chunk(session, piece_index, offset, data)
    {:ok, :no_change}
  end
end
