```elixir
defmodule MyApp.Events.ObservingAppendsFirstEvent do
  use Chronicle.Events.EventType, id: "observing-appends-first-event"

  defstruct [:data]
end

defmodule MyApp.Events.ObservingAppendsSecondEvent do
  use Chronicle.Events.EventType, id: "observing-appends-second-event"

  defstruct [:data]
end

defmodule MyApp.ObservingAppendsBatchCompletionWaiter do
  alias Chronicle.EventSequences.{AppendResult, EventLog}
  alias MyApp.Events.{ObservingAppendsFirstEvent, ObservingAppendsSecondEvent}

  def append_many_and_wait(event_source_id) do
    events = [
      %ObservingAppendsFirstEvent{data: "first"},
      %ObservingAppendsSecondEvent{data: "second"}
    ]

    case EventLog.append_many_with_result(event_source_id, events) do
      {:ok, %AppendResult{} = append_many_result} ->
        case AppendResult.wait_for_completion(append_many_result, timeout: 10_000) do
          {:ok, %{success: true}} ->
            :ok

          {:ok, %{success: false, failed_partitions: failed_partitions}} ->
            # Inspect failed partitions from affected observers
            {:error, {:failed_partitions, failed_partitions}}

          {:error, reason} ->
            {:error, reason}
        end

      # A failed append has nothing to wait for.
      {:error, %AppendResult{} = rejected} ->
        {:error, rejected}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
```
