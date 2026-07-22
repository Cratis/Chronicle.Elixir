# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Connections.LoadBalancerTest do
  use ExUnit.Case, async: true

  alias Chronicle.Connections.ConnectionString
  alias Chronicle.Connections.ConnectionString.ServerAddress
  alias Chronicle.Connections.LoadBalancer

  defp addresses(hosts) do
    Enum.map(hosts, fn host -> %ServerAddress{host: host, port: 35_000} end)
  end

  defp connection_string(load_balancer) do
    %{ConnectionString.default() | load_balancer: load_balancer, server_addresses: []}
  end

  describe "select/4 with no addresses" do
    test "returns an error" do
      cs = connection_string(:random)

      assert LoadBalancer.select([], cs, 0, fn _a, _addr, _cs -> {:error, :unused} end) ==
               {:error, :no_addresses}
    end
  end

  describe "select/4 with a single address" do
    test "returns it directly without probing, regardless of strategy" do
      [address] = addresses(["only-host"])
      cs = connection_string(:least_connections)

      probe_fun = fn _action, _addr, _cs -> flunk("should not probe with a single candidate") end

      assert LoadBalancer.select([address], cs, 0, probe_fun) == {:ok, address}
    end
  end

  describe "select/4 :round_robin" do
    test "cycles through addresses in order as the counter increments" do
      candidates = addresses(["host1", "host2", "host3"])
      cs = connection_string(:round_robin)
      probe_fun = fn _a, _addr, _cs -> flunk("round-robin should not probe") end

      picks =
        for counter <- 0..5 do
          {:ok, address} = LoadBalancer.select(candidates, cs, counter, probe_fun)
          address.host
        end

      assert picks == ["host1", "host2", "host3", "host1", "host2", "host3"]
    end

    test "the starting index follows the given counter, not always index 0" do
      candidates = addresses(["host1", "host2", "host3"])
      cs = connection_string(:round_robin)
      probe_fun = fn _a, _addr, _cs -> flunk("round-robin should not probe") end

      assert {:ok, %{host: "host2"}} = LoadBalancer.select(candidates, cs, 1, probe_fun)
      assert {:ok, %{host: "host3"}} = LoadBalancer.select(candidates, cs, 2, probe_fun)
    end
  end

  describe "select/4 :random" do
    test "always picks one of the candidates" do
      candidates = addresses(["host1", "host2", "host3"])
      cs = connection_string(:random)
      probe_fun = fn _a, _addr, _cs -> flunk("random should not probe") end

      for _ <- 1..20 do
        assert {:ok, address} = LoadBalancer.select(candidates, cs, 0, probe_fun)
        assert address in candidates
      end
    end
  end

  describe "select/5 :least_connections" do
    test "picks the address reporting the fewest connections" do
      candidates = addresses(["busy", "idle", "medium"])
      cs = connection_string(:least_connections)

      probe_fun = fn
        :count, %{host: "busy"}, _cs -> {:ok, 10}
        :count, %{host: "idle"}, _cs -> {:ok, 0}
        :count, %{host: "medium"}, _cs -> {:ok, 5}
        :reserve, _addr, _cs -> {:ok, :reserved}
      end

      assert {:ok, %{host: "idle"}} = LoadBalancer.select(candidates, cs, 0, probe_fun, 0)
    end

    test "reserves the winning address after selecting it" do
      test = self()
      candidates = addresses(["a", "b"])
      cs = connection_string(:least_connections)

      probe_fun = fn
        :count, %{host: "a"}, _cs -> {:ok, 0}
        :count, %{host: "b"}, _cs -> {:ok, 1}
        :reserve, address, _cs -> send(test, {:reserved, address.host}) && {:ok, :reserved}
      end

      assert {:ok, %{host: "a"}} = LoadBalancer.select(candidates, cs, 0, probe_fun, 0)
      assert_receive {:reserved, "a"}
    end

    test "breaks ties randomly among equally-loaded candidates" do
      candidates = addresses(["tied1", "tied2"])
      cs = connection_string(:least_connections)

      probe_fun = fn
        :count, _addr, _cs -> {:ok, 3}
        :reserve, _addr, _cs -> {:ok, :reserved}
      end

      picks =
        for _ <- 1..30 do
          {:ok, address} = LoadBalancer.select(candidates, cs, 0, probe_fun, 0)
          address.host
        end

      assert "tied1" in picks
      assert "tied2" in picks
    end

    test "falls back to a random pick when every probe fails" do
      candidates = addresses(["a", "b"])
      cs = connection_string(:least_connections)

      probe_fun = fn
        :count, _addr, _cs -> {:error, :econnrefused}
        :reserve, _addr, _cs -> {:error, :econnrefused}
      end

      assert {:ok, address} = LoadBalancer.select(candidates, cs, 0, probe_fun, 0)
      assert address in candidates
    end

    test "excludes unreachable candidates from selection when some probes succeed" do
      candidates = addresses(["reachable", "unreachable"])
      cs = connection_string(:least_connections)

      probe_fun = fn
        :count, %{host: "reachable"}, _cs -> {:ok, 100}
        :count, %{host: "unreachable"}, _cs -> {:error, :timeout}
        :reserve, _addr, _cs -> {:ok, :reserved}
      end

      assert {:ok, %{host: "reachable"}} = LoadBalancer.select(candidates, cs, 0, probe_fun, 0)
    end

    test "defaults jitter_max_ms to 250 when not given" do
      candidates = addresses(["a", "b"])
      cs = connection_string(:least_connections)
      probe_fun = fn _action, _addr, _cs -> {:error, :unused} end

      {elapsed_microseconds, {:ok, address}} =
        :timer.tc(fn -> LoadBalancer.select(candidates, cs, 0, probe_fun) end)

      assert address in candidates
      assert elapsed_microseconds >= 1_000
    end

    test "jitter_max_ms of 0 disables the pre-probe delay" do
      candidates = addresses(["a", "b"])
      cs = connection_string(:least_connections)

      probe_fun = fn
        :count, %{host: "a"}, _cs -> {:ok, 0}
        :count, %{host: "b"}, _cs -> {:ok, 1}
        :reserve, _addr, _cs -> {:ok, :reserved}
      end

      {elapsed_microseconds, {:ok, %{host: "a"}}} =
        :timer.tc(fn -> LoadBalancer.select(candidates, cs, 0, probe_fun, 0) end)

      assert elapsed_microseconds < 1_000
    end
  end
end
