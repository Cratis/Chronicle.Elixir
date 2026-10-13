# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.ReadModels.FilterTest do
  use ExUnit.Case, async: true

  alias Chronicle.ReadModels.Filter

  defmodule Entry do
    defstruct schema_id: "", amount: 0, tags: [], note: ""
  end

  defp entries do
    [
      %Entry{schema_id: "a", amount: 50, tags: ["x"], note: "paid in full"},
      %Entry{schema_id: "a", amount: 150, tags: ["x", "y"], note: "pending"},
      %Entry{schema_id: "b", amount: 250, tags: [], note: "paid late"}
    ]
  end

  test "equality and conjunction of conditions" do
    assert [%{amount: 150}] = Filter.apply(entries(), schema_id: "a", amount: {:gt, 100})
  end

  test "comparison operators" do
    assert length(Filter.apply(entries(), amount: {:gte, 150})) == 2
    assert length(Filter.apply(entries(), amount: {:lt, 150})) == 1
    assert length(Filter.apply(entries(), amount: {:lte, 150})) == 2
    assert length(Filter.apply(entries(), schema_id: {:ne, "a"})) == 1
  end

  test "in and contains" do
    assert length(Filter.apply(entries(), schema_id: {:in, ["b", "c"]})) == 1
    assert length(Filter.apply(entries(), note: {:contains, "paid"})) == 2
    assert length(Filter.apply(entries(), tags: {:contains, "y"})) == 1
  end

  test "an empty filter keeps everything" do
    assert Filter.apply(entries(), []) == entries()
  end

  test "sorting" do
    assert [250, 150, 50] = entries() |> Filter.sort({:amount, :desc}) |> Enum.map(& &1.amount)
    assert [50, 150, 250] = entries() |> Filter.sort(:amount) |> Enum.map(& &1.amount)
    assert Filter.sort(entries(), nil) == entries()
  end
end
