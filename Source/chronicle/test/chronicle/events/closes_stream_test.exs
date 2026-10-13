# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Events.ClosesStreamTest do
  use ExUnit.Case, async: true

  alias Chronicle.Events.Constraints

  defmodule PeriodReopened do
    use Chronicle.Events.EventType, id: "period-reopened"
    defstruct period: "", reason: ""
  end

  defmodule PeriodClosed do
    use Chronicle.Events.EventType, id: "period-closed"
    defstruct period: ""

    closes_stream(event_stream_id_from: :period, reopened_by: [PeriodReopened])
  end

  defmodule BooksClosed do
    use Chronicle.Events.EventType, id: "books-closed"
    defstruct year: 2000

    closes_stream(name: "books", dimensions: [:event_source_type])
  end

  defmodule BooksFinalized do
    use Chronicle.Events.EventType, id: "books-finalized"
    defstruct year: 2000

    closes_stream(name: "books", dimensions: [:event_source_type])
  end

  defmodule Mismatched do
    use Chronicle.Events.EventType, id: "books-mismatch"
    defstruct year: 2000

    closes_stream(name: "books", dimensions: [:event_source_id])
  end

  defp f(map, key), do: Map.fetch!(map, key)
  defp wire(definition), do: definition |> Constraints.build_constraint() |> elem(0)

  test "a closing event compiles to a ClosesStream constraint with the stream id property" do
    [definition] = Constraints.from_event_types([PeriodClosed, PeriodReopened])
    constraint = wire(definition)

    assert f(constraint, :Name) == "period-closed"
    assert f(constraint, :Type) == :ClosesStream
    closes = f(constraint, :ClosesStream)
    assert f(closes, :EventTypeIds) == ["period-closed"]
    assert f(closes, :ReopenedBy) == ["period-reopened"]
    assert f(closes, :EventStreamIdFrom) == "period"
    # event source id (1) + stream type (4) + stream id (8)
    assert f(closes, :Dimensions) == 13
  end

  test "declarations sharing a name merge into one constraint" do
    [definition] = Constraints.from_event_types([BooksClosed, BooksFinalized])
    closes = f(wire(definition), :ClosesStream)

    assert Enum.sort(f(closes, :EventTypeIds)) == ["books-closed", "books-finalized"]
    assert f(closes, :Dimensions) == 2
  end

  test "conflicting declarations under one name are rejected" do
    assert_raise ArgumentError, ~r/conflicting closes_stream/, fn ->
      Constraints.from_event_types([BooksClosed, Mismatched])
    end
  end

  test "a stream id property missing from the event is rejected" do
    defmodule NoProperty do
      use Chronicle.Events.EventType, id: "no-property"
      defstruct other: ""

      closes_stream(event_stream_id_from: :period)
    end

    assert_raise ArgumentError, ~r/does not exist/, fn ->
      Constraints.from_event_types([NoProperty])
    end
  end

  test "unknown dimensions are rejected" do
    defmodule BadDimension do
      use Chronicle.Events.EventType, id: "bad-dimension"
      defstruct []

      closes_stream(dimensions: [:nope])
    end

    assert_raise ArgumentError, ~r/unknown dimension/, fn ->
      Constraints.from_event_types([BadDimension])
    end
  end
end
