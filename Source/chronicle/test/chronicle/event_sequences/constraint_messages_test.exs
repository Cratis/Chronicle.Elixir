# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.EventSequences.ConstraintMessagesTest do
  use Chronicle.AppendWireCase, async: false

  alias Chronicle.EventSequences.AppendResponse

  defmodule EmailRegistered do
    use Chronicle.Events.EventType, id: "email-registered"
    defstruct [:email]
    unique(:email, name: "unique-email", message: "Email is already taken")
    unique_event_type(name: "single-registration", message: "Already registered")
    unique(:email, name: "no-message")
  end

  setup %{opts: opts} do
    client = Keyword.fetch!(opts, :client)
    config = Chronicle.Client.config(client)

    :persistent_term.put(
      {Chronicle.Client, client},
      Map.put(config, :event_types, [EmailRegistered])
    )

    :ok
  end

  for path <- [:single, :ordinary, :rich, :transaction, :wait] do
    test "#{path} applies declared messages without changing violation details", %{opts: opts} do
      violation = %Wire.ConstraintViolation{
        ConstraintName: "unique-email",
        Message: "kernel message",
        EventTypeId: "email-registered"
      }

      expected = %{violation | Message: "Email is already taken"}
      put_response(:append_payload, IsSuccess: false, ConstraintViolations: [violation])

      result =
        if unquote(path) == :wait,
          do: EventLog.append_and_wait_for_completion("source", %Event{}, opts),
          else: append(unquote(path), opts)

      assert {:error, {:constraint_violations, [^expected]}} = result
    end
  end

  test "transaction state retains resolved constraint messages", %{opts: opts} do
    violation = %Wire.ConstraintViolation{ConstraintName: "unique-email", Message: "kernel"}
    put_response(:append_payload, IsSuccess: false, ConstraintViolations: [violation])
    unit = UnitOfWork.begin()
    :ok = EventLog.append("source", %Event{}, opts)
    assert {:error, {:constraint_violations, [resolved]}} = UnitOfWork.commit(unit)
    assert Map.get(resolved, :Message) == "Email is already taken"
    assert Agent.get(unit, & &1.constraint_violations) == [resolved]
  end

  test "resolves unique-event-type messages and preserves kernel diagnostics otherwise" do
    violations =
      for name <- ["single-registration", "no-message", "schema"] do
        %Wire.ConstraintViolation{ConstraintName: name, Message: "kernel message"}
      end

    response = %{ConstraintViolations: violations}
    resolved = AppendResponse.resolve_messages(response, [EmailRegistered])
    assert [first, second, third] = Map.get(resolved, :ConstraintViolations)
    assert Map.get(first, :Message) == "Already registered"
    assert second == Enum.at(violations, 1)
    assert third == Enum.at(violations, 2)
    assert AppendResponse.resolve_messages(response, []) == response
  end

  test "supports snake-case responses and leaves malformed responses for normalization" do
    response = %{
      constraint_violations: [
        %{constraint_name: "unique-email", message: "kernel", details: "kept"}
      ]
    }

    assert %{constraint_violations: [%{message: "Email is already taken", details: "kept"}]} =
             AppendResponse.resolve_messages(response, [EmailRegistered])

    for response <- [nil, %{}, %{ConstraintViolations: nil}] do
      assert AppendResponse.resolve_messages(response, [EmailRegistered]) == response
    end
  end
end
