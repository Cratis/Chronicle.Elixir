# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Events.UniqueModeTest do
  use ExUnit.Case, async: true

  alias Chronicle.Events.Constraints

  defmodule Default do
    use Chronicle.Events.EventType, id: "mode-default"
    defstruct email: ""
    unique(:email)
  end

  defmodule PerValue do
    use Chronicle.Events.EventType, id: "mode-per-value"
    defstruct code: ""
    unique(:code, mode: :per_value)
  end

  defmodule BadMode do
    use Chronicle.Events.EventType, id: "mode-bad"
    defstruct code: ""
    unique(:code, mode: :sideways)
  end

  defp mode(module) do
    [definition] = Constraints.from_event_types([module])
    {constraint, _} = Constraints.build_constraint(definition)
    constraint |> Map.fetch!(:Definition) |> Map.fetch!(:Value0) |> Map.fetch!(:Mode)
  end

  test "the default mode keeps one value per event source" do
    assert mode(Default) == :PerEventSource
  end

  test "per_value retains every value until a removal event releases it" do
    assert mode(PerValue) == :PerValue
  end

  test "an unknown mode is rejected with a helpful message" do
    assert_raise ArgumentError, ~r/unknown :mode/, fn ->
      Constraints.from_event_types([BadMode])
    end
  end
end
