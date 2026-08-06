```elixir
defmodule MyApp.FailedPartitionsGetFor do
  def failed_partitions_for(observer_id) do
    Chronicle.FailedPartitions.get_for(observer_id)
  end
end
```
