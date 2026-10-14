# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.ReadModels.ObserveFilterTest do
  use ExUnit.Case, async: true

  alias Chronicle.ReadModels

  defmodule Entry do
    use Chronicle.ReadModels.ReadModel
    defstruct id: "", schema_id: "", amount: 0
  end

  defp request(page \\ 0, page_size \\ 50) do
    struct(Cratis.Chronicle.Contracts.ReadModels.ObserveInstancesRequest,
      Page: page,
      PageSize: page_size
    )
  end

  defp response(instances, total_count) do
    %{
      Instances: Enum.map(instances, &Jason.encode!(Map.from_struct(&1))),
      TotalCount: total_count,
      Page: 0,
      PageSize: 50
    }
  end

  describe "observe/2 argument validation" do
    test "rejects an unknown filter field without needing a connection" do
      assert ReadModels.observe(Entry, filter: [bogus: 1]) == {:error, {:unknown_field, :bogus}}
    end

    test "rejects an unknown sort field without needing a connection" do
      assert ReadModels.observe(Entry, sort: :bogus) == {:error, {:unknown_field, :bogus}}

      assert ReadModels.observe(Entry, sort: {:bogus, :desc}) ==
               {:error, {:unknown_field, :bogus}}
    end
  end

  describe "decode_observed_page/5" do
    test "passes the server's page and total_count through unfiltered" do
      entries = [%Entry{id: "1", schema_id: "a", amount: 10}]
      result = ReadModels.decode_observed_page(Entry, request(), response(entries, 5), [], nil)

      assert result.instances == entries
      assert result.total_count == 5
    end

    test "filters and sorts the delivered page, recomputing total_count from the matches" do
      entries = [
        %Entry{id: "1", schema_id: "a", amount: 150},
        %Entry{id: "2", schema_id: "b", amount: 50},
        %Entry{id: "3", schema_id: "a", amount: 200}
      ]

      result =
        ReadModels.decode_observed_page(
          Entry,
          request(),
          response(entries, 3),
          [schema_id: "a"],
          {:amount, :desc}
        )

      assert Enum.map(result.instances, & &1.id) == ["3", "1"]
      assert result.total_count == 2
    end
  end

  describe "observe_stream/2" do
    test "raises Chronicle.ReadModels.ObserveError when observe/2 cannot start" do
      assert_raise ReadModels.ObserveError, fn ->
        Entry |> ReadModels.observe_stream(filter: [bogus: 1]) |> Enum.take(1)
      end
    end
  end
end
