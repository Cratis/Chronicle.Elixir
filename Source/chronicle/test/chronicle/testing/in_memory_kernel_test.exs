# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Testing.InMemoryKernelTest do
  use ExUnit.Case, async: true

  import Chronicle.Testing.Assertions

  alias Chronicle.EventSequences.EventLog
  alias Chronicle.Events.ConcurrencyScope
  alias Chronicle.Testing

  defmodule AccountOpened do
    use Chronicle.Events.EventType, id: "testing-account-opened"
    defstruct [:owner_name, :initial_balance]
  end

  defmodule FundsDeposited do
    use Chronicle.Events.EventType, id: "testing-funds-deposited"
    defstruct [:amount]
  end

  defmodule UserRegistered do
    use Chronicle.Events.EventType, id: "testing-user-registered"

    unique([:email], name: "TestingUniqueEmail")

    defstruct [:email]
  end

  defmodule UserRemoved do
    use Chronicle.Events.EventType, id: "testing-user-removed"
    remove_constraint("TestingUniqueEmail")
    defstruct []
  end

  defmodule LoanCheckedOut do
    use Chronicle.Events.EventType, id: "testing-loan-checked-out"
    unique_event_type(name: "TestingOneOpenLoan")
    defstruct []
  end

  defmodule LoanReturned do
    use Chronicle.Events.EventType, id: "testing-loan-returned"
    remove_constraint("TestingOneOpenLoan")
    defstruct []
  end

  defmodule AccountReadModel do
    use Chronicle.ReadModels.ReadModel
    defstruct [:account_id, :owner_name, balance: 0]
  end

  defmodule AccountReducer do
    use Chronicle.Reducers.Reducer, model: AccountReadModel

    @handles AccountOpened
    @handles FundsDeposited

    @impl true
    def reduce(%AccountOpened{} = event, nil, _context) do
      %AccountReadModel{owner_name: event.owner_name, balance: event.initial_balance}
    end

    def reduce(%FundsDeposited{} = event, model, _context) do
      %{model | balance: model.balance + event.amount}
    end
  end

  defmodule WelcomeSentEvent do
    use Chronicle.Events.EventType, id: "testing-welcome-sent"
    defstruct []
  end

  defmodule WelcomeReactor do
    use Chronicle.Reactors.Reactor

    @handles AccountOpened

    @impl true
    def handle(%AccountOpened{}, _context), do: {:ok, %WelcomeSentEvent{}}
  end

  setup do
    {:ok, client} =
      Testing.start_supervised_client(
        event_types: [
          AccountOpened,
          FundsDeposited,
          UserRegistered,
          UserRemoved,
          LoanCheckedOut,
          LoanReturned,
          WelcomeSentEvent
        ],
        reducers: [AccountReducer],
        reactors: [WelcomeReactor]
      )

    on_exit(fn -> Testing.stop_supervised_client(client) end)
    %{client: client}
  end

  test "appends an event and asserts on it without a kernel", %{client: client} do
    :ok =
      EventLog.append("account-1", %AccountOpened{owner_name: "Alice", initial_balance: 100},
        client: client
      )

    assert_appended(client, %AccountOpened{owner_name: "Alice", initial_balance: 100},
      event_source_id: "account-1"
    )

    assert_appended(client, AccountOpened, event_source_id: "account-1", count: 1)
    refute_appended(client, FundsDeposited, event_source_id: "account-1")
  end

  test "a reducer runs deterministically and builds read model state", %{client: client} do
    :ok =
      EventLog.append("account-2", %AccountOpened{owner_name: "Bob", initial_balance: 50},
        client: client
      )

    :ok = EventLog.append("account-2", %FundsDeposited{amount: 25}, client: client)
    :ok = Testing.wait_for_observers(client)

    assert {:ok, %AccountReadModel{owner_name: "Bob", balance: 75}} =
             Testing.read_model(client, AccountReducer, "account-2")
  end

  test "a reactor's side effect is appended back to the in-memory log", %{client: client} do
    :ok =
      EventLog.append("account-3", %AccountOpened{owner_name: "Carol", initial_balance: 10},
        client: client
      )

    :ok = Testing.wait_for_observers(client)

    assert_appended(client, WelcomeSentEvent, event_source_id: "account-3")
  end

  test "a unique constraint rejects a duplicate value across event sources", %{client: client} do
    :ok = EventLog.append("user-1", %UserRegistered{email: "a@example.com"}, client: client)

    result = EventLog.append("user-2", %UserRegistered{email: "a@example.com"}, client: client)
    assert_constraint_violation(result, "TestingUniqueEmail")
  end

  test "removing the constraint-holding event frees the value for reuse", %{client: client} do
    :ok = EventLog.append("user-3", %UserRegistered{email: "b@example.com"}, client: client)
    :ok = EventLog.append("user-3", %UserRemoved{}, client: client)

    assert :ok =
             EventLog.append("user-4", %UserRegistered{email: "b@example.com"}, client: client)
  end

  test "a unique_event_type constraint rejects a second open loan for the same source", %{
    client: client
  } do
    :ok = EventLog.append("book-1", %LoanCheckedOut{}, client: client)
    result = EventLog.append("book-1", %LoanCheckedOut{}, client: client)
    assert_constraint_violation(result, "TestingOneOpenLoan")

    :ok = EventLog.append("book-1", %LoanReturned{}, client: client)
    assert :ok = EventLog.append("book-1", %LoanCheckedOut{}, client: client)
  end

  test "a concurrency scope expecting no matching event rejects a second append", %{
    client: client
  } do
    scope = ConcurrencyScope.expecting_no_matching_event(event_source_id: true)

    assert :ok =
             EventLog.append(
               "account-5",
               %AccountOpened{owner_name: "Dana", initial_balance: 0},
               client: client,
               concurrency_scope: scope
             )

    result =
      EventLog.append(
        "account-5",
        %AccountOpened{owner_name: "Dana", initial_balance: 0},
        client: client,
        concurrency_scope: scope
      )

    assert_concurrency_violation(result)
  end

  test "an optimistic concurrency scope at the wrong tail is rejected", %{client: client} do
    :ok =
      EventLog.append("account-6", %AccountOpened{owner_name: "Eve", initial_balance: 0},
        client: client
      )

    result =
      EventLog.append(
        "account-6",
        %FundsDeposited{amount: 5},
        client: client,
        concurrency_scope: ConcurrencyScope.for_event_source(5, event_source_id: true)
      )

    assert_concurrency_violation(result)
  end
end
