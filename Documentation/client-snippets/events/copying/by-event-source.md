```elixir
defmodule MyApp.CopyByEventSourceService do
  alias Chronicle.EventSequences.EventLog

  def copy_account(source_id, target_id) do
    {:ok, job_id} = EventLog.copy(source_id, target_id)
    job_id
  end
end
```
