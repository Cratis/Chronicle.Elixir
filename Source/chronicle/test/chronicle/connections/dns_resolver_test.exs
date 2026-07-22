# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Connections.DnsResolverTest do
  use ExUnit.Case, async: true

  alias Chronicle.Connections.ConnectionString.ServerAddress
  alias Chronicle.Connections.DnsResolver

  # The real `:inet_res`/`:inet_dns` calls behind `resolve/2` aren't exercised
  # here (that needs real DNS); `Chronicle.Connections.Connection` treats
  # `resolve_fun` as an injectable seam for exactly that reason, mirroring
  # `:connect_fun`. `to_addresses/1` is the pure ordering/conversion logic and
  # is tested directly against plain SRV answer tuples instead.

  describe "to_addresses/1" do
    test "converts SRV tuples into ServerAddress structs" do
      records = [{10, 50, 35_000, ~c"host1"}]

      assert DnsResolver.to_addresses(records) == [
               %ServerAddress{host: "host1", port: 35_000}
             ]
    end

    test "accepts binary targets as well as charlists" do
      records = [{10, 50, 35_000, "host1"}]
      assert DnsResolver.to_addresses(records) == [%ServerAddress{host: "host1", port: 35_000}]
    end

    test "sorts ascending by priority" do
      records = [
        {20, 0, 35_000, ~c"low-priority"},
        {10, 0, 35_000, ~c"high-priority"}
      ]

      assert Enum.map(DnsResolver.to_addresses(records), & &1.host) == [
               "high-priority",
               "low-priority"
             ]
    end

    test "sorts descending by weight within the same priority" do
      records = [
        {10, 10, 35_000, ~c"light"},
        {10, 90, 35_000, ~c"heavy"}
      ]

      assert Enum.map(DnsResolver.to_addresses(records), & &1.host) == ["heavy", "light"]
    end

    test "priority takes precedence over weight" do
      records = [
        {10, 1, 35_000, ~c"low-priority-low-weight"},
        {20, 100, 35_000, ~c"high-priority-high-weight"}
      ]

      assert Enum.map(DnsResolver.to_addresses(records), & &1.host) == [
               "low-priority-low-weight",
               "high-priority-high-weight"
             ]
    end

    test "returns an empty list for no records" do
      assert DnsResolver.to_addresses([]) == []
    end
  end
end
