# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Testing.ProjectionsTest do
  use ExUnit.Case, async: true

  alias Chronicle.Testing.{Projections, UnsupportedProjectionOperation}

  defmodule AccountOpened do
    use Chronicle.Events.EventType, id: "projections-account-opened"
    defstruct [:owner_name, :initial_balance]
  end

  defmodule FundsDeposited do
    use Chronicle.Events.EventType, id: "projections-funds-deposited"
    defstruct [:amount]
  end

  defmodule AccountClosed do
    use Chronicle.Events.EventType, id: "projections-account-closed"
    defstruct []
  end

  defmodule UnrelatedEvent do
    use Chronicle.Events.EventType, id: "projections-unrelated"
    defstruct []
  end

  defmodule Account do
    use Chronicle.ReadModels.ReadModel

    defstruct [:owner_name, balance: 0, deposit_count: 0]

    from(AccountOpened, set: [owner_name: :owner_name, balance: :initial_balance])
    from(FundsDeposited, add: [balance: :amount], count: :deposit_count)
    removed_with(AccountClosed, [])
  end

  defmodule Joined do
    use Chronicle.ReadModels.ReadModel
    defstruct [:value]

    from(AccountOpened, set: [value: :owner_name])
    join(FundsDeposited, on: "accountId", set: [value: :amount])
  end

  test "from/2 :set and :add/:count accumulate across events" do
    {:ok, instance} =
      Projections.apply_event(Account, nil, %AccountOpened{
        owner_name: "Alice",
        initial_balance: 10
      })

    assert %Account{owner_name: "Alice", balance: 10, deposit_count: 0} = instance

    {:ok, instance} = Projections.apply_event(Account, instance, %FundsDeposited{amount: 5})
    assert %Account{balance: 15, deposit_count: 1} = instance
  end

  test "removed_with/2 removes the instance" do
    {:ok, instance} =
      Projections.apply_event(Account, nil, %AccountOpened{owner_name: "Bob", initial_balance: 0})

    assert :removed = Projections.apply_event(Account, instance, %AccountClosed{})
  end

  test "an event the read model does not declare from/2 for leaves the instance unchanged" do
    instance = %Account{owner_name: "Carol", balance: 3}
    assert {:ok, ^instance} = Projections.apply_event(Account, instance, %UnrelatedEvent{})
  end

  test "join/2 raises UnsupportedProjectionOperation" do
    assert_raise UnsupportedProjectionOperation, ~r/declares join/, fn ->
      Projections.apply_event(Joined, nil, %AccountOpened{owner_name: "Dana", initial_balance: 0})
    end
  end
end
