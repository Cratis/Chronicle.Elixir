```elixir
defmodule MyApp.JobsIndexListAll do
  def get_all_jobs do
    Cratis.Chronicle.Jobs.all()
  end
end
```
