```elixir
defmodule MyApp.JobsIndexGetOne do
  def get_job(job_id) do
    Cratis.Chronicle.Jobs.get(job_id)
  end
end
```
