```elixir
defmodule MyApp.Events.ConcurrencyMoneyWithdrawnForTransfer do
  use Chronicle.Events.EventType, id: "concurrency-money-withdrawn-for-transfer"

  defstruct [:amount]
end

defmodule MyApp.Events.ConcurrencyMoneyDepositedForTransfer do
  use Chronicle.Events.EventType, id: "concurrency-money-deposited-for-transfer"

  defstruct [:amount]
end

defmodule MyApp.ConcurrencyTransferService do
  alias Chronicle.Events.ConcurrencyScope
  alias Chronicle.Transactions.UnitOfWork
  alias MyApp.Events.{ConcurrencyMoneyDepositedForTransfer, ConcurrencyMoneyWithdrawnForTransfer}

  def transfer_money(from_account, to_account, amount) do
    unit_of_work = UnitOfWork.begin()

    try do
      :ok =
        Chronicle.append(
          from_account,
          %ConcurrencyMoneyWithdrawnForTransfer{amount: amount},
          concurrency_scope: ConcurrencyScope.for_event_source(50)
        )

      :ok =
        Chronicle.append(
          to_account,
          %ConcurrencyMoneyDepositedForTransfer{amount: amount},
          concurrency_scope: ConcurrencyScope.for_event_source(25)
        )

      :ok = UnitOfWork.commit(unit_of_work)
    rescue
      exception ->
        UnitOfWork.rollback(unit_of_work)
        reraise exception, __STACKTRACE__
    end
  end
end
```
