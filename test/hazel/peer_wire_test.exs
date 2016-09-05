defmodule Hazel.PeerWireTest do
  use ExUnit.Case, async: true

  alias Hazel.PeerWire

  describe "encoding" do
    test "keep alive messages" do
      assert <<0, 0, 0, 0>> = PeerWire.encode(:keep_alive)
    end

    test "choke messages" do
      assert <<0, 0, 0, 1, 0>> = PeerWire.encode({:choke, true})
    end

    test "unchoke messages" do
      assert <<0, 0, 0, 1, 1>> = PeerWire.encode({:choke, false})
    end

    test "interested messages" do
      assert <<0, 0, 0, 1, 2>> = PeerWire.encode({:interest, true})
    end

    test "not interested messages" do
      assert <<0, 0, 0, 1, 3>> = PeerWire.encode({:interest, false})
    end

    test "have messages" do
      assert <<0, 0, 0, 5, 4, 0, 0, 0, 1>> = PeerWire.encode({:have, 1})
    end

    test "bit field messages" do
      assert <<0, 0, 0, 5, 5, 0, 128, 2, 1>> = PeerWire.encode({:bit_field, <<0, 128, 2, 1>>})
    end

    test "request messages" do
      assert <<0, 0, 0, 13, 6, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 10>> =
        PeerWire.encode({:request, 0, 0, 10})
    end

    test "piece messages" do
      assert <<0, 0, 0, 15, 7, 0, 0, 1, 65, 0, 0, 0, 128, 0, 1, 2, 3, 4, 5>> =
        PeerWire.encode({:piece, 321, 128, <<0,1,2,3,4,5>>})
    end

    test "cancel messages" do
      assert <<0, 0, 0, 13, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 10>> =
        PeerWire.encode({:cancel, 0, 0, 10})
    end
  end

  describe "encoding coding" do
    test "keep alive messages" do
      assert :keep_alive = PeerWire.decode(<<0, 0, 0, 0>>)
    end

    test "choke messages" do
      assert {:choke, true} = PeerWire.decode(<<0, 0, 0, 1, 0>>)
    end

    test "unchoke messages" do
      assert {:choke, false} = PeerWire.decode(<<0, 0, 0, 1, 1>>)
    end

    test "interested messages" do
      assert {:interest, true} = PeerWire.decode(<<0, 0, 0, 1, 2>>)
    end

    test "not interested messages" do
      assert {:interest, false} = PeerWire.decode(<<0, 0, 0, 1, 3>>)
    end

    test "have messages" do
      assert {:have, 1} = PeerWire.decode(<<0, 0, 0, 5, 4, 0, 0, 0, 1>>)
    end

    test "bit field messages" do
      assert {:bit_field, <<0, 128, 2, 1>>} = PeerWire.decode(<<0, 0, 0, 5, 5, 0, 128, 2, 1>>)
    end

    test "request messages" do
      assert {:request, 0, 0, 10} =
        PeerWire.decode(<<0, 0, 0, 13, 6, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 10>>)
    end

    test "piece messages" do
      assert {:piece, 321, 128, <<0,1,2,3,4,5>>} =
        PeerWire.decode(<<0, 0, 0, 15, 7, 0, 0, 1, 65, 0, 0, 0, 128, 0, 1, 2, 3, 4, 5>>)
    end

    test "cancel messages" do
      assert {:cancel, 0, 0, 10} =
        PeerWire.decode(<<0, 0, 0, 13, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 10>>)
    end
  end
end
