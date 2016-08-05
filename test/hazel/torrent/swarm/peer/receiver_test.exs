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

  defp peer_controller_via_name({{local_id, info_hash}, peer_id}) do
    {Controller, local_id, info_hash, peer_id}
  end

  test "starting a receiver" do
    session = generate_session()
    {:ok, pid} = start_receiver(session)
    assert is_pid(pid)
  end

  test "receiving an await message" do
    session = generate_session()
    {:ok, receiver_pid} = start_receiver(session)

    Hazel.TestHelpers.FauxServerDeux.start_link(
      peer_controller_via_name(session),
      [receiver_pid: receiver_pid, cb:
       [request_tokens:
        fn _message, state ->
          :ok = Receiver.add_tokens(state[:receiver_pid], 4)
        end,

        receive:
        fn <<0,0,0,0>> = message, state ->
          send state[:pid], message
          :ok
        end
       ]])

    {:ok, client} = create_and_attach_client_to_receiver(receiver_pid)
    assert :ok = :gen_tcp.send(client, <<0,0,0,0>>)
    assert_receive <<0,0,0,0>>
  end

  test "receiving a bunch of messages in a row" do
    session = generate_session()
    {:ok, receiver_pid} = start_receiver(session)

    Hazel.TestHelpers.FauxServerDeux.start_link(
      peer_controller_via_name(session),
      [receiver_pid: receiver_pid, cb:
       [request_tokens:
        fn _, state ->
          :ok = Receiver.add_tokens(state[:receiver_pid], 300)
        end,

        receive:
        fn message, state ->
          send state[:pid], message
          :ok
        end
       ]])

    messages = [<<0,0,0,1,0>>, <<0,0,0,1,1>>,
                <<0,0,0,1,2>>, <<0,0,0,1,3>>,
                <<0,0,0,1,4>>]

    {:ok, client} = create_and_attach_client_to_receiver(receiver_pid)
    assert :ok = :gen_tcp.send(client, IO.iodata_to_binary(messages))
    for message <- messages, do: assert_receive ^message
  end

  test "should not receive after running out of tokens" do
    session = generate_session()
    {:ok, receiver_pid} = start_receiver(session)

    Hazel.TestHelpers.FauxServerDeux.start_link(
      peer_controller_via_name(session),
      [receiver_pid: receiver_pid, tokens: 10, cb:
       [request_tokens:
        fn
          _, state ->
            tokens = state[:tokens]
            if (tokens > 0) do
              # give enough tokens to receive a message
              Receiver.add_tokens(state[:receiver_pid], 5)
              {:ok, Keyword.put(state, :tokens, tokens - 5)}
            else
              :ok
            end
        end,

        receive:
        fn message, state ->
          send state[:pid], message
          :ok
        end
       ]])

    messages = [<<0,0,0,1,0>>, <<0,0,0,1,1>>, <<0,0,0,1,2>>]

    {:ok, client} = create_and_attach_client_to_receiver(receiver_pid)
    assert :ok = :gen_tcp.send(client, IO.iodata_to_binary(messages))

    {received_messages, non_received_messages} = Enum.split(messages, 2)
    for message <- received_messages, do: assert_receive ^message
    should_not_receive = hd non_received_messages
    refute_receive ^should_not_receive
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
    new_state =
      if is_function(state[:cb][command]) do
        case apply(state[:cb][command], args ++ [state]) do
          {:ok, state} when is_list(state) ->
            state

          :ok ->
            state

          _ ->
            raise ArgumentError,
              message: "should return `{:ok, state}`-tuple or just `:ok`"
        end
      else
        state
      end

    {:noreply, new_state}
  end

  def handle_call(message, _from, state) do
    # todo, fix handle_calls
    [command|args] = Tuple.to_list(message)
    {reply, new_state} =
      if is_function(state[:cb][command]) do
        apply(state[:cb][command], args ++ [state])
      end
    {:reply, reply, new_state}
  end
end
