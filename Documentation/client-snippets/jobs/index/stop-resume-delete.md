```elixir
defmodule MyApp.JobsIndexStopResumeDelete do
  def stop_job(job_id), do: Cratis.Chronicle.Jobs.stop(job_id)
  def resume_job(job_id), do: Cratis.Chronicle.Jobs.resume(job_id)
  def delete_job(job_id), do: Cratis.Chronicle.Jobs.delete(job_id)
end
```
