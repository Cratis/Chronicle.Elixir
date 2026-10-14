# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Captures.CaptureTest do
  use ExUnit.Case, async: true

  alias Chronicle.Captures.{
    MissingAppendCondition,
    MissingCaptureKey,
    MissingCaptureSourceConfiguration
  }

  defmodule InvoiceStatusChanged do
    use Chronicle.Events.EventType, id: "ItInvoiceStatusChanged"
    defstruct status: "", changed_at: ""
  end

  defmodule BillingAddressChanged do
    use Chronicle.Events.EventType, id: "ItBillingAddressChanged"
    defstruct street: ""
  end

  defmodule ItemAdded do
    use Chronicle.Events.EventType, id: "ItItemAdded"
    defstruct line_number: 0
  end

  # The kernel's CDL compiler requires an append's event type to start with an uppercase letter
  # (confirmed against a real kernel via ValidateCaptureDeclaration: a lowercase-leading id
  # fails "Invalid append declaration '...' - expected 'append <EventType>'"), so we reject it
  # here instead, at compile time, with a message that says what to do about it. `from` (events
  # source) has no such restriction - it is free-form text in the real grammar.
  defmodule HyphenatedEvent do
    use Chronicle.Events.EventType, id: "it-hyphenated-event"
    defstruct status: ""
  end

  defmodule InvoiceCapture do
    use Chronicle.Captures.Capture, name: "InvoiceCapture", start: true

    api_source("InvoicingApi", route: "/invoices", poll: "10m")

    key("id")

    map do
      translate(:status, :status, [{"utkast", "draft"}, {"betalt", "paid"}])
    end

    append InvoiceStatusChanged, when: "status" do
      set(:status, "$.status")
      set(:changed_at, "$context.occurred")
    end

    nested :billing_address do
      map do
        rename(:street, :"billingAddress.street")
      end

      append BillingAddressChanged, when: "street" do
        set(:street, "$.street")
      end
    end

    children :line_items, identified_by: :line_number do
      append ItemAdded, when: :added do
        set(:line_number, "$.lineNumber")
      end
    end
  end

  describe "use Chronicle.Captures.Capture" do
    test "exposes a deterministic id by default" do
      assert InvoiceCapture.__chronicle_capture__(:id) ==
               Chronicle.Captures.Declaration.deterministic_id(InvoiceCapture)
    end

    test "exposes the configured name" do
      assert InvoiceCapture.__chronicle_capture__(:name) == "InvoiceCapture"
    end

    test "exposes start?" do
      assert InvoiceCapture.__chronicle_capture__(:start?) == true
    end

    test "compiles the full declaration" do
      assert InvoiceCapture.__chronicle_capture__(:declaration) == """
             capture InvoiceCapture
               source api
                 api InvoicingApi
                 route /invoices
                 poll 10m
               key id
               map
                 status = status translate
                   "utkast" => "draft"
                   "betalt" => "paid"
               append ItInvoiceStatusChanged
                 when status
                 status = $.status
                 changedAt = $context.occurred
               nested billing_address
                 map
                   street = billingAddress.street
                 append ItBillingAddressChanged
                   when street
                   street = $.street
               children line_items identified by line_number
                 append ItItemAdded
                   when added
                   lineNumber = $.lineNumber
             """
    end
  end

  describe "an explicit id and omitted name" do
    defmodule Unnamed do
      use Chronicle.Captures.Capture, id: "11111111-1111-5111-8111-111111111111"
      webhook_source("/unnamed")
      key("id")

      append InvoiceStatusChanged, when: :added do
        set(:status, "$.status")
      end
    end

    test "uses the explicit id" do
      assert Unnamed.__chronicle_capture__(:id) == "11111111-1111-5111-8111-111111111111"
    end

    test "defaults the name to the module's last segment" do
      assert Unnamed.__chronicle_capture__(:name) == "Unnamed"
    end

    test "defaults start? to false" do
      assert Unnamed.__chronicle_capture__(:start?) == false
    end
  end

  describe "an events source" do
    defmodule EventsCapture do
      use Chronicle.Captures.Capture, name: "EventsCapture"
      events_source([InvoiceStatusChanged, BillingAddressChanged])
      key("$eventSourceId")

      append ItemAdded, when: :added do
        set(:line_number, "$.lineNumber")
      end
    end

    test "resolves each event module to its registered event type id" do
      assert EventsCapture.__chronicle_capture__(:declaration) =~ "from ItInvoiceStatusChanged"

      assert EventsCapture.__chronicle_capture__(:declaration) =~
               "from ItBillingAddressChanged"
    end
  end

  describe "compile errors" do
    test "a capture without a source raises MissingCaptureSourceConfiguration" do
      assert_raise MissingCaptureSourceConfiguration, ~r/must declare a source/, fn ->
        Code.compile_string("""
        defmodule Chronicle.Captures.CaptureTest.NoSource do
          use Chronicle.Captures.Capture, name: "NoSource"
          key "id"
        end
        """)
      end
    end

    test "a capture with two sources raises MissingCaptureSourceConfiguration" do
      assert_raise MissingCaptureSourceConfiguration, ~r/declares 2 sources/, fn ->
        Code.compile_string("""
        defmodule Chronicle.Captures.CaptureTest.DuplicateSource do
          use Chronicle.Captures.Capture, name: "DuplicateSource"
          api_source "Api"
          webhook_source "/hook"
          key "id"
        end
        """)
      end
    end

    test "a capture without a key raises MissingCaptureKey" do
      assert_raise MissingCaptureKey, ~r/must declare a key/, fn ->
        Code.compile_string("""
        defmodule Chronicle.Captures.CaptureTest.NoKey do
          use Chronicle.Captures.Capture, name: "NoKey"
          webhook_source "/hook"
        end
        """)
      end
    end

    test "an append without when: raises MissingAppendCondition" do
      assert_raise MissingAppendCondition, ~r/missing a `when:` option/, fn ->
        Code.compile_string("""
        defmodule Chronicle.Captures.CaptureTest.NoWhen do
          use Chronicle.Captures.Capture, name: "NoWhen"
          webhook_source "/hook"
          key "id"

          append Chronicle.Captures.CaptureTest.InvoiceStatusChanged do
            set :status, "$.status"
          end
        end
        """)
      end
    end

    test "set targeting a field that is not on the event struct raises TargetPropertyMustBeAProperty" do
      assert_raise Chronicle.Captures.TargetPropertyMustBeAProperty,
                   ~r/must point to a property/,
                   fn ->
                     Code.compile_string("""
                     defmodule Chronicle.Captures.CaptureTest.BadTarget do
                       use Chronicle.Captures.Capture, name: "BadTarget"
                       webhook_source "/hook"
                       key "id"

                       append Chronicle.Captures.CaptureTest.InvoiceStatusChanged, when: :added do
                         set :not_a_real_field, "$.status"
                       end
                     end
                     """)
                   end
    end

    test "appending a hyphenated event type id raises ArgumentError" do
      assert_raise ArgumentError, ~r/cannot be an append target/, fn ->
        Code.compile_string("""
        defmodule Chronicle.Captures.CaptureTest.HyphenatedAppend do
          use Chronicle.Captures.Capture, name: "HyphenatedAppend"
          webhook_source "/hook"
          key "id"

          append Chronicle.Captures.CaptureTest.HyphenatedEvent, when: :added do
            set :status, "$.status"
          end
        end
        """)
      end
    end

    test "an events_source accepts a lowercase or hyphenated event type id (from is unrestricted)" do
      Code.compile_string("""
      defmodule Chronicle.Captures.CaptureTest.HyphenatedEventsSource do
        use Chronicle.Captures.Capture, name: "HyphenatedEventsSource"
        events_source [Chronicle.Captures.CaptureTest.HyphenatedEvent]
        key "$eventSourceId"

        append Chronicle.Captures.CaptureTest.ItemAdded, when: :added do
          set :line_number, "$.lineNumber"
        end
      end
      """)

      assert apply(
               Chronicle.Captures.CaptureTest.HyphenatedEventsSource,
               :__chronicle_capture__,
               [
                 :declaration
               ]
             ) =~ "from it-hyphenated-event"
    end
  end
end
