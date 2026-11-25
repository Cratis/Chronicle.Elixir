```elixir
defmodule MyApp.Events.SeeTheGuardMoneyWithdrawn do
  use Cratis.Chronicle.Events.EventType, id: "see-the-guard-money-withdrawn"

  defstruct [:amount]
end

# Counts the withdrawals in the stream the read is scoped to.
defmodule MyApp.ReadModels.SeeTheGuardMonthlyWithdrawals do
  use Cratis.Chronicle.ReadModels.ReadModel, passive: true

  defstruct id: nil, count: 0

  from MyApp.Events.SeeTheGuardMoneyWithdrawn, set: [id: :event_source_id], count: :count
end

defmodule MyApp.SeeTheGuardShowTheGuard do
  alias Cratis.Chronicle.ReadModels.DecisionReads
  alias Cratis.Chronicle.Transactions.UnitOfWork
  alias MyApp.ReadModels.SeeTheGuardMonthlyWithdrawals

  def withdraw(account_id) do
    unit_of_work = UnitOfWork.begin()

    # Account, stream type "Transactions", stream id "2026-10".
    {:ok, _read} =
      DecisionReads.get(SeeTheGuardMonthlyWithdrawals, account_id, "Transactions", "2026-10")

    # One concurrency scope per guarded event source. Inspect it to see what a commit would guard.
    guards = UnitOfWork.get_decision_reads(unit_of_work)

    UnitOfWork.rollback(unit_of_work)
    guards
  end
end
```
