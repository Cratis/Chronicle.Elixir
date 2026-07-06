```elixir
defmodule MyApp.JobsIndexGetSteps do
  def get_steps(job_id) do
    Chronicle.Jobs.steps(job_id)
  end
end
```
