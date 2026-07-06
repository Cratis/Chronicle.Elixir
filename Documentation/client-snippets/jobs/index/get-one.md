```elixir
defmodule MyApp.JobsIndexGetOne do
  def get_job(job_id) do
    Chronicle.Jobs.get(job_id)
  end
end
```
