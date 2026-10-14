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

  defp compile_warnings(source) do
    ExUnit.CaptureIO.capture_io(:stderr, fn -> Code.eval_string(source) end)
  end

  test "an unknown mode warns at compile time and still raises when the definition is built" do
    warnings =
      compile_warnings("""
      defmodule Chronicle.Events.UniqueModeTest.BadMode do
        use Chronicle.Events.EventType, id: "mode-bad"
        defstruct code: ""
        unique(:code, mode: :sideways)
      end
      """)

    assert warnings =~ "invalid :mode :sideways"
    assert warnings =~ "Chronicle.Events.UniqueModeTest.BadMode"

    assert_raise ArgumentError, ~r/unknown :mode :sideways/, fn ->
      Constraints.from_event_types([Chronicle.Events.UniqueModeTest.BadMode])
    end
  end

  test "an unknown unique/2 option warns at compile time and is ignored" do
    warnings =
      compile_warnings("""
      defmodule Chronicle.Events.UniqueModeTest.BadOption do
        use Chronicle.Events.EventType, id: "mode-bad-option"
        defstruct code: ""
        unique(:code, not_a_real_option: true)
      end
      """)

    assert warnings =~ "unique/2 has unknown option(s) [:not_a_real_option]"
    assert [_] = Constraints.from_event_types([Chronicle.Events.UniqueModeTest.BadOption])
  end

  test "an invalid unique/2 scope warns at compile time" do
    warnings =
      compile_warnings("""
      defmodule Chronicle.Events.UniqueModeTest.BadScope do
        use Chronicle.Events.EventType, id: "mode-bad-scope"
        defstruct code: ""
        unique(:code, scope: :sideways)
      end
      """)

    assert warnings =~ "invalid :scope [:sideways]"
  end

  test "an unknown unique_event_type/1 option warns at compile time" do
    warnings =
      compile_warnings("""
      defmodule Chronicle.Events.UniqueModeTest.BadUniqueEventTypeOption do
        use Chronicle.Events.EventType, id: "mode-bad-uet-option"
        defstruct []
        unique_event_type(mode: :per_value)
      end
      """)

    assert warnings =~ "unique_event_type/1 has unknown option(s) [:mode]"
  end

  test "options that are not a literal keyword list are not validated at compile time" do
    assert compile_warnings("""
           defmodule Chronicle.Events.UniqueModeTest.AttributeOpts do
             use Chronicle.Events.EventType, id: "mode-attribute-opts"
             defstruct code: ""
             @opts [mode: :per_value]
             unique(:code, @opts)
           end
           """) == ""
  end
end
