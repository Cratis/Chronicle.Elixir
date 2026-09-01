```elixir
defmodule MyApp.Events.ObservingAppendsSomeEvent do
  use Chronicle.Events.EventType, id: "observing-appends-some-event"

  defstruct [:data]
end

defmodule MyApp.ObservingAppendsCompletionWaiter do
  alias Chronicle.EventSequences.EventLog
  alias MyApp.Events.ObservingAppendsSomeEvent

  def append_and_wait(event_source_id) do
    case EventLog.append_and_wait_for_completion(event_source_id, %ObservingAppendsSomeEvent{
           data: "example"
         }) do
      {:ok, %{success: true}} ->
        :ok

      {:ok, %{success: false, failed_partitions: failed_partitions}} ->
        Enum.each(failed_partitions, fn failed_partition ->
          IO.puts("Observer failed partition: #{inspect(failed_partition)}")
        end)

      {:error, reason} ->
        {:error, reason}
    end
  end
end
```
