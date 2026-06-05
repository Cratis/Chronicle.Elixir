# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Events.ConcurrencyScopeTest do
  use ExUnit.Case, async: true

  alias Chronicle.Events.ConcurrencyScope

  defmodule FundsDeposited do
    use Chronicle.EventType, id: "funds-deposited-v1"
    defstruct [:amount]
  end

  test "creates a scope for the current event source" do
    scope =
      ConcurrencyScope.for_event_source(12,
        event_stream_type: :accounting,
        event_stream_id: :primary,
        event_source_type: :account,
        event_types: [FundsDeposited]
      )

    assert scope == %ConcurrencyScope{
             sequence_number: 12,
             event_source_id: true,
             event_stream_type: "accounting",
             event_stream_id: "primary",
             event_source_type: "account",
             event_types: [FundsDeposited]
           }
  end

  test "normalizes keyword options into a scope" do
    scope = ConcurrencyScope.normalize(sequence_number: 7, event_source_type: :bank_account)

    assert scope.sequence_number == 7
    assert scope.event_source_type == "bank_account"
    refute scope.event_source_id
  end

  test "returns the none scope when omitted" do
    assert ConcurrencyScope.normalize(nil) == ConcurrencyScope.none()
  end

  test "requires a sequence number for keyword options" do
    assert_raise ArgumentError, ~r/:sequence_number/, fn ->
      ConcurrencyScope.normalize(event_source_id: true)
    end
  end
end
