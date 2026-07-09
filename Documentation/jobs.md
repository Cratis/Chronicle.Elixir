# Jobs

`Chronicle.Jobs` provides an idiomatic Elixir API for inspecting and controlling Chronicle jobs.

Jobs represent long-running Chronicle operations such as replays, rebuilds, and other background work performed by the Chronicle Kernel.

## Starting point

Start `Chronicle.Client` first:

```elixir
children = [
  {Chronicle.Client,
    connection_string: "chronicle://localhost:35000",
    event_store: "banking",
    otp_app: :my_app}
]
```

Once the client is running, use `Chronicle.Jobs`:

```elixir
{:ok, jobs} = Chronicle.Jobs.all()
{:ok, job} = Chronicle.Jobs.get("8a6f5a0c-0fbf-42bd-8db0-a60f9a449b11")
{:ok, steps} = Chronicle.Jobs.steps("8a6f5a0c-0fbf-42bd-8db0-a60f9a449b11")
```

## API

### List all jobs

```elixir
{:ok, jobs} = Chronicle.Jobs.all()
```

Each job is returned as `%Chronicle.Jobs.Job{}` with:

- `:id`
- `:details`
- `:type`
- `:status`
- `:created_at`
- `:status_changes`
- `:progress`

### Get one job

```elixir
{:ok, job} = Chronicle.Jobs.get(job_id)
```

Returns `{:ok, nil}` when the job does not exist.

### Get job steps

```elixir
{:ok, steps} = Chronicle.Jobs.steps(job_id)
```

Each step is returned as `%Chronicle.Jobs.JobStep{}`.

### Stop, resume, and delete

```elixir
:ok = Chronicle.Jobs.stop(job_id)
:ok = Chronicle.Jobs.resume(job_id)
:ok = Chronicle.Jobs.delete(job_id)
```

## Status values

Job statuses are normalized to atoms:

- `:none`
- `:preparing_job`
- `:preparing_steps`
- `:starting_steps`
- `:running`
- `:completed_successfully`
- `:completed_with_failures`
- `:stopped`
- `:failed`
- `:removing`

Job-step statuses are normalized to atoms:

- `:unknown`
- `:scheduled`
- `:running`
- `:completed_successfully`
- `:completed_with_failure`
- `:stopped`
- `:failed`
- `:removing`

## Using a named client

```elixir
{:ok, jobs} = Chronicle.Jobs.all(client: :bank_chronicle)
```

## Top-level convenience helpers

`Chronicle` also delegates to the jobs API:

```elixir
{:ok, jobs} = Chronicle.get_jobs()
{:ok, job} = Chronicle.get_job(job_id)
{:ok, steps} = Chronicle.get_job_steps(job_id)
:ok = Chronicle.stop_job(job_id)
```
