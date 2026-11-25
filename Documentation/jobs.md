---
title: Jobs
description: List, inspect, stop, resume and delete Chronicle jobs such as replays from Elixir, and follow a job's progress and steps in an event store.
---

Inspect a job's progress and steps in the selected client's event store and namespace with `Cratis.Chronicle.Jobs`.

Jobs represent long-running Chronicle operations such as replays, rebuilds, and other background work performed by the Chronicle Kernel.

## Starting point

Start `Cratis.Chronicle.Client` first:

```elixir
children = [
  {Cratis.Chronicle.Client,
    connection_string: "chronicle://chronicle-dev-client:chronicle-dev-secret@localhost:35000",
    event_store: "banking",
    otp_app: :my_app}
]
```

Once the client is running, use `Cratis.Chronicle.Jobs`:

```elixir
{:ok, jobs} = Cratis.Chronicle.Jobs.all()
{:ok, job} = Cratis.Chronicle.Jobs.get("8a6f5a0c-0fbf-42bd-8db0-a60f9a449b11")
{:ok, steps} = Cratis.Chronicle.Jobs.steps("8a6f5a0c-0fbf-42bd-8db0-a60f9a449b11")
```

## API

### List all jobs

```elixir
{:ok, jobs} = Cratis.Chronicle.Jobs.all()
```

Each job is returned as `%Cratis.Chronicle.Jobs.Job{}` with:

- `:id`
- `:details`
- `:type`
- `:status`
- `:created_at`
- `:status_changes`
- `:progress`

### Get one job

```elixir
{:ok, job} = Cratis.Chronicle.Jobs.get(job_id)
```

Returns `{:ok, nil}` when the job does not exist.

### Get job steps

```elixir
{:ok, steps} = Cratis.Chronicle.Jobs.steps(job_id)
```

Each step is returned as `%Cratis.Chronicle.Jobs.JobStep{}`.

### Stop, resume, and delete

Choose stop, resume or delete for the job you inspected; these are alternatives, not a sequence to run.
Confirm the job id, client/namespace and authority before a control request, then inspect status again.
A successful request is not a promise that background work has completed or that cancellation has finished.

```elixir
:ok = Cratis.Chronicle.Jobs.stop(job_id)
:ok = Cratis.Chronicle.Jobs.resume(job_id)
:ok = Cratis.Chronicle.Jobs.delete(job_id)
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
{:ok, jobs} = Cratis.Chronicle.Jobs.all(client: :bank_chronicle)
```

## Top-level convenience helpers

`Chronicle` also delegates to the jobs API:

```elixir
{:ok, jobs} = Cratis.Chronicle.get_jobs()
{:ok, job} = Cratis.Chronicle.get_job(job_id)
{:ok, steps} = Cratis.Chronicle.get_job_steps(job_id)
:ok = Cratis.Chronicle.stop_job(job_id)
```
