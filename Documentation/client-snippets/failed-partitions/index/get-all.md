```elixir
defmodule MyApp.FailedPartitionsGetAll do
  def all_failed_partitions do
    Cratis.Chronicle.FailedPartitions.get_all()
  end
end
```
