```elixir
defmodule MyApp.Events.MonthlyLimitMoneyWithdrawn do
  use Chronicle.Events.EventType, id: "monthly-limit-money-withdrawn"

  defstruct [:amount]
end

# Names the source type and the stream, so the read and the append use the same values.
defmodule MyApp.MonthlyLimitBankAccountEventSource do
  use Chronicle.EventSources.EventSource, name: "BankAccount"

  stream "Transactions", description: "Deposits and withdrawals, one stream per month"
end

# The decision model: what this account has withdrawn in the stream the read is scoped to.
defmodule MyApp.ReadModels.MonthlyLimitWithdrawnThisMonth do
  use Chronicle.ReadModels.ReadModel, passive: true

  defstruct id: nil, total: 0

  from MyApp.Events.MonthlyLimitMoneyWithdrawn, set: [id: :event_source_id], add: [total: :amount]
end

defmodule MyApp.MonthlyLimitWithdraw do
  alias Chronicle.EventSequences.EventLog
  alias Chronicle.ReadModels.{DecisionConflict, DecisionReads}
  alias MyApp.Events.MonthlyLimitMoneyWithdrawn
  alias MyApp.MonthlyLimitBankAccountEventSource
  alias MyApp.ReadModels.MonthlyLimitWithdrawnThisMonth

  @monthly_limit 5000

  # month is the stream id, for example "2026-10".
  def handle(account_id, month, amount) do
    result =
      Chronicle.decide(fn _unit_of_work ->
        # Reads only BankAccount / Transactions / month, and guards only that stream.
        {:ok, read} =
          DecisionReads.get(
            MonthlyLimitWithdrawnThisMonth,
            account_id,
            "Transactions",
            month,
            event_source_type: "BankAccount"
          )

        withdrawn = if read.instance, do: read.instance.total, else: 0

        if withdrawn + amount > @monthly_limit do
          :monthly_limit_reached
        else
          :ok =
            EventLog.append(account_id, %MonthlyLimitMoneyWithdrawn{amount: amount},
              event_source: MonthlyLimitBankAccountEventSource,
              event_stream: "Transactions",
              event_stream_id: month
            )

          :withdrawn
        end
      end)

    case result do
      {:ok, outcome} -> outcome
      # A withdrawal in this month's stream was appended after the read. Nothing was appended.
      {:error, %DecisionConflict{}} -> :changed_concurrently
      {:error, _reason} -> :failed
    end
  end
end
```
