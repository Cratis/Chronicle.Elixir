```elixir
defmodule MyApp.FailedPartitionsGetAll do
  def all_failed_partitions do
    Chronicle.FailedPartitions.get_all()
  end
end
```
