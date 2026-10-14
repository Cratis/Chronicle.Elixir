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

  test "an unknown mode is rejected at compile time with a helpful message" do
    assert_raise CompileError, ~r/invalid :mode :sideways/, fn ->
      Code.eval_string("""
      defmodule Chronicle.Events.UniqueModeTest.BadMode do
        use Chronicle.Events.EventType, id: "mode-bad"
        defstruct code: ""
        unique(:code, mode: :sideways)
      end
      """)
    end
  end

  test "an unknown unique/2 option is rejected at compile time" do
    assert_raise CompileError, ~r/unique\/2 has unknown option\(s\) \[:not_a_real_option\]/, fn ->
      Code.eval_string("""
      defmodule Chronicle.Events.UniqueModeTest.BadOption do
        use Chronicle.Events.EventType, id: "mode-bad-option"
        defstruct code: ""
        unique(:code, not_a_real_option: true)
      end
      """)
    end
  end

  test "an invalid unique/2 scope is rejected at compile time" do
    assert_raise CompileError, ~r/invalid :scope \[:sideways\]/, fn ->
      Code.eval_string("""
      defmodule Chronicle.Events.UniqueModeTest.BadScope do
        use Chronicle.Events.EventType, id: "mode-bad-scope"
        defstruct code: ""
        unique(:code, scope: :sideways)
      end
      """)
    end
  end

  test "an unknown unique_event_type/1 option is rejected at compile time" do
    assert_raise CompileError, ~r/unique_event_type\/1 has unknown option\(s\) \[:mode\]/, fn ->
      Code.eval_string("""
      defmodule Chronicle.Events.UniqueModeTest.BadUniqueEventTypeOption do
        use Chronicle.Events.EventType, id: "mode-bad-uet-option"
        defstruct []
        unique_event_type(mode: :per_value)
      end
      """)
    end
  end
end
