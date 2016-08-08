defmodule Hazel.Torrent.Swarm.Peer.TransmitterTest do
  use ExUnit.Case

  alias Hazel.Torrent.Swarm.Peer.{Controller, Transmitter}

  defp generate_session() do
    local_id = Hazel.generate_peer_id()
    peer_id = Hazel.generate_peer_id()
    info_hash = :crypto.strong_rand_bytes(20)

    {{local_id, info_hash}, peer_id}
  end

  defp start_transmitter({session, peer_id}) do
    Transmitter.start_link(session, peer_id)
  end

  # generate a TCP acceptor on a random port and use that to
  # attach a client to a receiver
  defp create_and_attach_client_to_transmitter(transmitter_pid) do
    {:ok, acceptor} = FauxAcceptorDeux.start_link()
    {:ok, {ip, port}} = FauxAcceptorDeux.get_info(acceptor)
    :ok = FauxAcceptorDeux.accept(acceptor, transmitter_pid)
    :gen_tcp.connect(ip, port, active: false)
  end

  defp peer_controller_via_name({{local_id, info_hash}, peer_id}) do
    {Controller, local_id, info_hash, peer_id}
  end

  defp get_current_state(pid) do
    {:status, _, _, [_|[_,_,_,hi]]} = :sys.get_status(pid)
    [_,[{'State', {current_state, internal_state}}]] = Keyword.get_values(hi, :data)
    {current_state, internal_state}
  end

  test "starting a receiver" do
    session = generate_session()
    {:ok, pid} = start_transmitter(session)
    assert is_pid(pid)
  end

  test "appending an await message to the job queue" do
    session = generate_session()
    {:ok, pid} = start_transmitter(session)

    Hazel.TestHelpers.FauxServerDeux.start_link(
      peer_controller_via_name(session),
      [transmitter_pid: pid, cb: []])

    {:ok, _client} = create_and_attach_client_to_transmitter(pid)
    :timer.sleep 100
    Transmitter.append(pid, :await)

    {_current_state, internal_state} = get_current_state(pid)
    assert %Transmitter{job_queue: {[:await], []}} = internal_state
  end
end

defmodule FauxAcceptorDeux do
  use GenServer

  defstruct [socket: nil]

  # Client API
  def start_link() do
    GenServer.start_link(__MODULE__, %__MODULE__{})
  end

  def get_info(pid) do
    GenServer.call(pid, :info)
  end

  def accept(pid, transmitter_pid) do
    GenServer.cast(pid, {:accept, transmitter_pid})
  end

  # Server callbacks
  def init(state) do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false])
    {:ok, %{state|socket: socket}}
  end

  def handle_call(:info, _from, state) do
    {:reply, :inet.sockname(state.socket), state}
  end

  def handle_cast({:accept, transmitter_pid}, state) do
    {:ok, client} = :gen_tcp.accept(state.socket)
    :ok = :gen_tcp.controlling_process(client, transmitter_pid)
    :ok = Hazel.Torrent.Swarm.Peer.Transmitter.handover_socket(transmitter_pid, {:gen_tcp, client})
    {:noreply, state}
  end
end
