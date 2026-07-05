```elixir
defmodule MyApp.JobsIndexStopResumeDelete do
  def stop_job(job_id), do: Chronicle.Jobs.stop(job_id)
  def resume_job(job_id), do: Chronicle.Jobs.resume(job_id)
  def delete_job(job_id), do: Chronicle.Jobs.delete(job_id)
end
```
