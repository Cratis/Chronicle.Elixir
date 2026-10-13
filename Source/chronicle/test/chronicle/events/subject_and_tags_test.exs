# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Events.SubjectAndTagsTest do
  use ExUnit.Case, async: true

  alias Chronicle.Events.EventType

  defmodule CustomerId do
    use Chronicle.Concept, type: :string
  end

  defmodule Registered do
    use Chronicle.Events.EventType,
      id: "subject-registered",
      subject: :customer_id,
      tags: ["billing", :audit]

    defstruct customer_id: %CustomerId{}, email: ""
  end

  defmodule Plain do
    use Chronicle.Events.EventType, id: "subject-plain"
    defstruct customer_id: ""
  end

  defmodule Raw do
    use Chronicle.Events.EventType, id: "subject-raw", subject: :who
    defstruct who: ""
  end

  test "resolves the declared subject, unwrapping concepts" do
    assert EventType.declared_subject(%Registered{customer_id: %CustomerId{value: "c-1"}}) ==
             "c-1"
  end

  test "a raw string field also works and an empty one gives nil" do
    assert EventType.declared_subject(struct(Raw, who: "w")) == "w"
    assert EventType.declared_subject(%Raw{}) == nil
  end

  test "an event type without a declared subject has none" do
    assert EventType.declared_subject(%Plain{customer_id: "x"}) == nil
  end

  test "static tags are declared per event type" do
    assert EventType.declared_tags(%Registered{}) == ["billing", "audit"]
    assert EventType.declared_tags(%Plain{}) == []
  end
end
