```elixir
defmodule MyApp.Events.PerStreamSavingsWithdrawn do
  use Cratis.Chronicle.Events.EventType, id: "per-stream-savings-withdrawn"

  defstruct amount: 0
end

defmodule MyApp.PerStreamSavingsAccountEventSource do
  use Cratis.Chronicle.EventSources.EventSource, name: "SavingsAccount"

  stream "Transactions", description: "Withdrawals, one stream per month"
end

# Passive and keyed by the account; the decision read selects the month's stream.
defmodule MyApp.ReadModels.PerStreamWithdrawnInMonth do
  use Cratis.Chronicle.ReadModels.ReadModel, passive: true

  defstruct id: nil, total: 0

  from MyApp.Events.PerStreamSavingsWithdrawn, set: [id: :event_source_id], add: [total: :amount]
end

defmodule MyApp.PerStreamWithdrawSavings do
  alias Cratis.Chronicle.EventSequences.EventLog
  alias Cratis.Chronicle.ReadModels.{DecisionConflict, DecisionReads}
  alias MyApp.Events.PerStreamSavingsWithdrawn
  alias MyApp.PerStreamSavingsAccountEventSource
  alias MyApp.ReadModels.PerStreamWithdrawnInMonth

  @monthly_limit 5000

  # month is the stream id, for example "2026-10".
  def handle(account_id, month, amount) do
    result =
      Cratis.Chronicle.decide(fn _unit_of_work ->
        {:ok, read} =
          DecisionReads.get(
            PerStreamWithdrawnInMonth,
            account_id,
            "Transactions",
            month,
            event_source_type: "SavingsAccount"
          )

        withdrawn = if read.instance, do: read.instance.total, else: 0

        if withdrawn + amount > @monthly_limit do
          :monthly_limit_reached
        else
          # The append uses exactly the route protected by the decision read.
          :ok =
            EventLog.append(account_id, %PerStreamSavingsWithdrawn{amount: amount},
              event_source: PerStreamSavingsAccountEventSource,
              event_stream: "Transactions",
              event_stream_id: month
            )

          :withdrawn
        end
      end)

    case result do
      {:ok, outcome} -> outcome
      # A competing withdrawal changed this month's stream. Nothing was appended.
      {:error, %DecisionConflict{}} -> :changed_concurrently
      {:error, _reason} -> :failed
    end
  end
end
```
