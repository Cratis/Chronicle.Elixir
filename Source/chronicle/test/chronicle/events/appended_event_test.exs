# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Events.AppendedEventTest do
  use ExUnit.Case, async: true

  alias Chronicle.Events.AppendedEvent

  defmodule Item do
    defstruct item_name: ""
  end

  defmodule BasketUpdated do
    use Chronicle.Events.EventType, id: "basket-updated", types: [line_items: {:list, Item}]
    defstruct owner_name: "", line_items: []
  end

  defp wire(type_id, content) do
    %{
      Context: %{
        EventType: %{Id: type_id, Generation: 1},
        EventSourceId: "b-1",
        SequenceNumber: 3
      },
      Content: Jason.encode!(content)
    }
  end

  test "decodes a registered event type into its struct" do
    appended =
      wire("basket-updated", %{"ownerName" => "Ada", "lineItems" => [%{"itemName" => "tea"}]})

    assert %AppendedEvent{event: event, context: context, redacted?: false} =
             AppendedEvent.from_wire(appended, [BasketUpdated])

    assert event == %BasketUpdated{owner_name: "Ada", line_items: [%Item{item_name: "tea"}]}
    assert context.sequence_number == 3
  end

  test "an unknown event type keeps the raw content and has no struct" do
    appended = wire("something-else", %{"fooBar" => 1})

    assert %AppendedEvent{event: nil, raw: %{"fooBar" => 1}} =
             AppendedEvent.from_wire(appended, [BasketUpdated])
  end

  test "redacted events are represented explicitly" do
    appended =
      wire("EventRedacted", %{"reason" => "gdpr", "originalEventType" => "basket-updated"})

    assert %AppendedEvent{redacted?: true, event: nil, redaction: redaction} =
             AppendedEvent.from_wire(appended, [BasketUpdated])

    assert redaction == %{reason: "gdpr", original_event_type: "basket-updated"}
  end
end
