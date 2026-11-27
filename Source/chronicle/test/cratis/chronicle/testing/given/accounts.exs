# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Cratis.Chronicle.Testing.Given.Accounts do
  @moduledoc "Accounts, to specify the scenarios against: events, a projected read model, a reducer and a reactor."

  defmodule AccountOpened do
    use Cratis.Chronicle.Events.EventType, id: "scenario-account-opened"

    # An account is opened once.
    unique_event_type(
      name: "scenario-account-opened-once",
      message: "The account is already open."
    )

    defstruct [:owner_name, initial_balance: 0]
  end

  defmodule FundsDeposited do
    use Cratis.Chronicle.Events.EventType, id: "scenario-funds-deposited"
    defstruct [:amount]
  end

  defmodule WelcomeSent do
    use Cratis.Chronicle.Events.EventType, id: "scenario-welcome-sent"
    defstruct []
  end

  defmodule Account do
    @moduledoc "Built by a projection."
    use Cratis.Chronicle.ReadModels.ReadModel

    defstruct [:owner_name, balance: 0]

    from(AccountOpened, set: [owner_name: :owner_name, balance: :initial_balance])
    from(FundsDeposited, add: [balance: :amount])
  end

  defmodule Balance do
    @moduledoc "Built by a reducer."
    use Cratis.Chronicle.ReadModels.ReadModel
    defstruct balance: 0
  end

  defmodule BalanceReducer do
    use Cratis.Chronicle.Reducers.Reducer, model: Balance

    @handles AccountOpened
    @handles FundsDeposited

    @impl true
    def reduce(%AccountOpened{initial_balance: balance}, nil, _context),
      do: %Balance{balance: balance}

    def reduce(%FundsDeposited{amount: amount}, balance, _context),
      do: %{balance | balance: balance.balance + amount}
  end

  defmodule WelcomeReactor do
    use Cratis.Chronicle.Reactors.Reactor

    @handles AccountOpened

    @impl true
    def handle(%AccountOpened{}, _context), do: {:ok, %WelcomeSent{}}
  end

  defmodule FailingReactor do
    use Cratis.Chronicle.Reactors.Reactor

    @handles FundsDeposited

    @impl true
    def handle(%FundsDeposited{}, _context), do: {:error, :the_ledger_is_closed}
  end

  def event_types, do: [AccountOpened, FundsDeposited, WelcomeSent]
end
