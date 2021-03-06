defmodule HazelTest do
  use ExUnit.Case, async: true
  doctest Hazel

  describe "peer_id generation" do
    test "should generate unique peer_ids" do
      target = 100
      assert ^target =
        Stream.repeatedly(&Hazel.generate_peer_id/0)
        |> Stream.take(target)
        |> Stream.uniq
        |> Enum.to_list
        |> length
    end

    test "peer_ids should be 20 bytes long" do
      Stream.repeatedly(&Hazel.generate_peer_id/0)
      |> Stream.take(100)
      |> Stream.filter(fn peer_id -> assert byte_size(peer_id) == 20 end)
      |> Stream.run()
    end
  end
end
