defmodule HazelTest do
  use ExUnit.Case
  doctest Hazel

  describe "peer_id generation" do
    test "should generate unique peer_ids" do
      target = 100
      assert ^target =
        Stream.repeatedly(&Hazel.generate_peer_id/0)
        |> Enum.take(target)
        |> Enum.uniq
        |> length
    end

    test "peer_ids should be 20 bytes long" do
      target = 100
      assert ^target =
        Stream.repeatedly(&Hazel.generate_peer_id/0)
        |> Enum.take(target)
        |> Enum.filter(fn peer_id -> byte_size(peer_id) == 20 end)
        |> length
    end
  end
end
