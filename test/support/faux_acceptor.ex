defmodule Hazel.TestHelpers.FauxAcceptor do
  @moduledoc """
  Create a TCP-acceptor that will create network sockets for testing
  """
  use GenServer

  defstruct [socket: nil, controller_mod: nil]

  # Client API
  def start_link(controller_mod) do
    initial_state = %__MODULE__{controller_mod: controller_mod}
    GenServer.start_link(__MODULE__, initial_state)
  end

  def get_info(pid),
    do: GenServer.call(pid, :info)

  def accept(pid, process_pid),
    do: GenServer.cast(pid, {:accept, process_pid})

  # Server callbacks
  def init(state) do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false])
    {:ok, %{state|socket: socket}}
  end

  def handle_call(:info, _from, state) do
    {:reply, :inet.sockname(state.socket), state}
  end

  def handle_cast({:accept, process_pid}, state) do
    {:ok, client} = :gen_tcp.accept(state.socket)
    :ok = :gen_tcp.controlling_process(client, process_pid)
    :ok = apply(state.controller_mod, :handover_socket, [process_pid, {:gen_tcp, client}])
    {:noreply, state}
  end
end
