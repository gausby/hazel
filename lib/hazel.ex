defmodule Hazel do
  @moduledoc """
  The main Hazel application
  """

  use Application

  def start(_type, _args) do
    opts = []
    Hazel.Supervisor.start_link(generate_peer_id(), opts)
  end

  @spec open(Path.t) :: {Map.t, info_hash :: binary()} | {:error, reason :: any()}
  def open(path) do
    case File.read(path) do
      {:ok, data} ->
        Bencode.decode_with_info_hash!(data)

      {:error, _reason} = error ->
        error
    end
  end

  # todo move?
  def generate_peer_id() do
    random_number_stream = Stream.repeatedly(fn -> ?9 - (:rand.uniform(10) - 1) end)
    header = "-HZ0001-"
    IO.iodata_to_binary [header, Enum.take(random_number_stream, 20 - byte_size header)]
  end
end
