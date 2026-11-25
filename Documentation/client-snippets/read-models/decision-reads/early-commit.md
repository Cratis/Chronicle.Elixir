```elixir
defmodule MyApp.Events.DecisionReadsEarlyOrderPlaced do
  use Cratis.Chronicle.Events.EventType, id: "decision-reads-early-order-placed"

  defstruct []
end

defmodule MyApp.ReadModels.DecisionReadsEarlyOrderEligibility do
  use Cratis.Chronicle.ReadModels.ReadModel

  defstruct id: nil, placed: 0

  from MyApp.Events.DecisionReadsEarlyOrderPlaced, set: [id: :event_source_id], add: [placed: 1]
end

defmodule MyApp.DecisionReadsEarlyCommit do
  alias Cratis.Chronicle.EventSequences.EventLog
  alias Cratis.Chronicle.ReadModels.{DecisionConflict, DecisionReads}
  alias MyApp.Events.DecisionReadsEarlyOrderPlaced
  alias MyApp.ReadModels.DecisionReadsEarlyOrderEligibility

  # Cratis.Chronicle.decide/2 commits as soon as the function returns, so the outcome is known
  # while you can still choose the response.
  def place(order_id) do
    outcome =
      Cratis.Chronicle.decide(fn _unit_of_work ->
        {:ok, read} = DecisionReads.get(DecisionReadsEarlyOrderEligibility, order_id)

        if read.instance == nil do
          :ok = EventLog.append(order_id, %DecisionReadsEarlyOrderPlaced{})
        end
      end)

    case outcome do
      {:ok, _} ->
        :no_content

      # Re-read and retry the decision in a new request.
      {:error, %DecisionConflict{}} ->
        :conflict

      # Constraint violations and other append failures.
      {:error, _reason} ->
        :unprocessable_entity
    end
  end
end
```
