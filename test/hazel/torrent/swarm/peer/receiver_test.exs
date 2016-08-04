defmodule Hazel.Torrent.Swarm.Peer.ReceiverTest do
  use ExUnit.Case

  alias Hazel.Torrent.Swarm.Peer.{Controller, Receiver}

  defp generate_session() do
    local_id = Hazel.generate_peer_id()
    peer_id = Hazel.generate_peer_id()
    info_hash = :crypto.strong_rand_bytes(20)

    {{local_id, info_hash}, peer_id}
  end

  defp start_receiver({session, peer_id}) do
    Receiver.start_link(session, peer_id)
  end

  # generate a TCP acceptor on a random port and use that to
  # attach a client to a receiver
  defp create_and_attach_client_to_receiver(receiver_pid) do
    {:ok, acceptor} = FauxAcceptor.start_link()
    {:ok, {ip, port}} = FauxAcceptor.get_info(acceptor)
    :ok = FauxAcceptor.accept(acceptor, receiver_pid)

    :gen_tcp.connect(ip, port, active: false)
  end

  test "starting a receiver" do
    session = generate_session()
    {:ok, pid} = start_receiver(session)
    assert is_pid(pid)
  end

  test "receiving an await message" do
    {{local_id, info_hash}, peer_id} = session = generate_session()
    {:ok, receiver_pid} = start_receiver(session)

    Hazel.TestHelpers.FauxServerDeux.start_link(
      {Controller, local_id, info_hash, peer_id},
      [receiver_pid: receiver_pid, cb:
       [request_tokens:
        fn _, state ->
          Receiver.add_tokens(state[:receiver_pid], 4)
        end,

        receive:
        fn <<0,0,0,0>> = message, state ->
          send state[:pid], message
        end
       ]])

    {:ok, client} = create_and_attach_client_to_receiver(receiver_pid)

    assert :ok = :gen_tcp.send(client, <<0,0,0,0>>)
    assert_receive <<0,0,0,0>>
  end
end

defmodule FauxAcceptor do
  use GenServer

  defstruct [socket: nil]

  # Client API
  def start_link() do
    GenServer.start_link(__MODULE__, %__MODULE__{})
  end

  def get_info(pid) do
    GenServer.call(pid, :info)
  end

  def accept(pid, receiver_pid) do
    GenServer.cast(pid, {:accept, receiver_pid})
  end

  # Server callbacks
  def init(state) do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false])
    {:ok, %{state|socket: socket}}
  end

  def handle_call(:info, _from, state) do
    {:reply, :inet.sockname(state.socket), state}
  end

  def handle_cast({:accept, receiver_pid}, state) do
    {:ok, client} = :gen_tcp.accept(state.socket)
    :ok = :gen_tcp.controlling_process(client, receiver_pid)
    :ok = Hazel.Torrent.Swarm.Peer.Receiver.handover_socket(receiver_pid, {:gen_tcp, client})
    {:noreply, state}
  end
end

defmodule Hazel.TestHelpers.FauxServerDeux do
  use GenServer

  # Client API
  def start_link(session, opts \\ []) do
    opts = Keyword.merge(opts, pid: self, session: session)
    GenServer.start_link(__MODULE__, opts, name: via_name(session))
  end

  defp via_name(session), do: {:via, :gproc, faux_name(session)}
  defp faux_name(session), do: {:n, :l, session}

  # Server callbacks
  def init(state), do: {:ok, state}

  def handle_cast(message, state) do
    [command|args] = Tuple.to_list(message)
    if is_function(state[:cb][command]) do
      apply(state[:cb][command], args ++ [Keyword.delete(state, :cb)])
    end
    {:noreply, state}
  end

  def handle_call(message, _from, state) do
    [command|args] = Tuple.to_list(message)
    reply =
      if is_function(state[:cb][command]) do
        apply(state[:cb][command], args ++ [Keyword.delete(state, :cb)])
      end
    {:reply, reply, state}
  end
end
