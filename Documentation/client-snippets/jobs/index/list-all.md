```elixir
defmodule MyApp.JobsIndexListAll do
  def get_all_jobs do
    Chronicle.Jobs.all()
  end
end
```
