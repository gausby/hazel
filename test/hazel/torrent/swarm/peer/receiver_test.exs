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
    {:ok, acceptor} = FauxAcceptor.start_link(Receiver)
    {:ok, {ip, port}} = FauxAcceptor.get_info(acceptor)
    :ok = FauxAcceptor.accept(acceptor, receiver_pid)

    :gen_tcp.connect(ip, port, [:binary, active: false])
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
