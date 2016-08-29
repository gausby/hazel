defmodule Hazel.Torrent.Swarm.Peer.TransmitterTest do
  use ExUnit.Case, async: true

  import Hazel.TestHelpers, only: [generate_peer_id: 0]

  alias Hazel.TestHelpers.FauxServer
  alias Hazel.Torrent.Swarm.Peer.{Controller, Transmitter}

  defp generate_session() do
    local_id = generate_peer_id()
    peer_id = generate_peer_id()
    info_hash = :crypto.strong_rand_bytes(20)

    {{local_id, info_hash}, peer_id}
  end

  defp start_transmitter({session, peer_id}) do
    Transmitter.start_link(session, peer_id)
  end

  # generate a TCP acceptor on a random port and use that to
  # attach a client to a receiver
  defp create_and_attach_client_to_transmitter(transmitter_pid) do
    {:ok, acceptor} = FauxAcceptor.start_link(Transmitter)
    {:ok, {ip, port}} = FauxAcceptor.get_info(acceptor)
    :ok = FauxAcceptor.accept(acceptor, transmitter_pid)
    :gen_tcp.connect(ip, port, [:binary, active: false])
  end

  defp peer_controller_via_name({{local_id, info_hash}, peer_id}) do
    {Controller, local_id, info_hash, peer_id}
  end

  defp get_current_state(pid) do
    {:status, _, _, [_|[_,_,_, state]]} = :sys.get_status(pid)
    [_,[{'State', {current_state, internal_state}}]] = Keyword.get_values(state, :data)
    {current_state, internal_state}
  end

  test "starting a receiver" do
    session = generate_session()
    {:ok, pid} = start_transmitter(session)
    assert is_pid(pid)
  end

  test "appending an awake message to the job queue" do
    session = generate_session()
    {:ok, pid} = start_transmitter(session)

    FauxServer.start_link(peer_controller_via_name(session))

    {:ok, _client} = create_and_attach_client_to_transmitter(pid)
    :timer.sleep 100
    Transmitter.append(pid, :awake)

    {_current_state, internal_state} = get_current_state(pid)
    assert %Transmitter{job_queue: {[:awake], []}} = internal_state
  end

  test "transmitting an awake message" do
    session = generate_session()
    {:ok, pid} = start_transmitter(session)
    FauxServer.start_link(
      peer_controller_via_name(session),
      [cb: [
          transmit:
          fn message, state ->
            send state[:pid], message
            :ok
          end
        ]])

    {:ok, client} = create_and_attach_client_to_transmitter(pid)
    :timer.sleep 100
    Transmitter.append(pid, :awake)
    Transmitter.add_tokens(pid, 4)

    assert {:ok, <<0, 0, 0, 0>>} = :gen_tcp.recv(client, 0)
    {_current_state, internal_state} = get_current_state(pid)
    assert {[], []} = internal_state.job_queue
    # the controller should receive the outgoing message
    assert_receive :awake
  end

  test "should throttle bytes sent" do
    session = generate_session()
    {:ok, pid} = start_transmitter(session)

    FauxServer.start_link(peer_controller_via_name(session))

    {:ok, client} = create_and_attach_client_to_transmitter(pid)
    :timer.sleep 100
    Transmitter.append(pid, :awake)
    Transmitter.add_tokens(pid, 2)

    assert {:ok, <<0, 0>>} = :gen_tcp.recv(client, 0)
    {_current_state, internal_state} = get_current_state(pid)
    assert <<0, 0>> = internal_state.current_job
  end

  test "sending a message with a length" do
    session = generate_session()
    {:ok, pid} = start_transmitter(session)

    FauxServer.start_link(peer_controller_via_name(session))

    {:ok, client} = create_and_attach_client_to_transmitter(pid)
    :timer.sleep 100
    Transmitter.append(pid, {:have, 329})
    Transmitter.add_tokens(pid, 200)

    assert {:ok, <<0, 0, 0, 5, 4, 0, 0, 1, 73>>} = :gen_tcp.recv(client, 0)
    {_current_state, internal_state} = get_current_state(pid)
    assert nil == internal_state.current_job
  end

  test "sending multiple messages" do
    session = generate_session()
    {:ok, pid} = start_transmitter(session)

    FauxServer.start_link(peer_controller_via_name(session),
      [cb: [
          transmit:
          fn message, state ->
            send state[:pid], message
            :ok
          end
        ]])

    {:ok, client} = create_and_attach_client_to_transmitter(pid)
    :timer.sleep 100
    Transmitter.append(pid, [{:have, 329}, :awake, {:request, 330, 2, 30}])
    Transmitter.add_tokens(pid, 2000)

    {:ok, _} = :gen_tcp.recv(client, 0)
    assert_receive {:have, 329}
    assert_receive :awake
    assert_receive {:request, 330, 2, 30}

    {_current_state, internal_state} = get_current_state(pid)
    assert nil == internal_state.current_job
  end

  test "should not add the same job if it is already queued" do
    session = generate_session()
    {:ok, pid} = start_transmitter(session)

    FauxServer.start_link(peer_controller_via_name(session))

    {:ok, _client} = create_and_attach_client_to_transmitter(pid)
    :timer.sleep 100
    Transmitter.append(pid, [:awake, :awake, :awake])

    {_current_state, internal_state} = get_current_state(pid)
    assert {[:awake], []} == internal_state.job_queue
  end

  test "should be able to insert a job in the start of the queue" do
    session = generate_session()
    {:ok, pid} = start_transmitter(session)

    FauxServer.start_link(peer_controller_via_name(session))

    {:ok, _client} = create_and_attach_client_to_transmitter(pid)
    :timer.sleep 100
    Transmitter.append(pid, {:choke, true})
    Transmitter.prepend(pid, :awake)

    {_current_state, internal_state} = get_current_state(pid)
    assert {[{:choke, true}], [:awake]} == internal_state.job_queue
  end

  test "if a prepended job is already in the queue it should be moved to the front" do
    session = generate_session()
    {:ok, pid} = start_transmitter(session)

    FauxServer.start_link(peer_controller_via_name(session))

    {:ok, _client} = create_and_attach_client_to_transmitter(pid)
    :timer.sleep 100
    Transmitter.append(pid, [{:choke, true}, {:have, 4}, {:interest, false}])
    Transmitter.prepend(pid, {:interest, false})

    {_current_state, internal_state} = get_current_state(pid)
    assert {[{:have, 4}], [{:interest, false}, {:choke, true}]} == internal_state.job_queue
  end
end
