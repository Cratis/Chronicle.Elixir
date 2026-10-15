---
title: Dynamic Consistency Boundary
description: Guard a decision with a decision read so a concurrent append can never invalidate it silently.
---

Dynamic Consistency Boundary (DCB) in Chronicle, decision reads, and event sources and the DCB
are documented as shared Chronicle concepts. Read those first for the model and its rules.

- [Dynamic Consistency Boundary in Chronicle](/chronicle/dynamic-consistency-boundary/)
- [Decision reads](/chronicle/read-models/decision-reads/)
- [Event sources and the Dynamic Consistency Boundary](/chronicle/event-sources/dcb/)
- [Elixir client setup](./get-started.md)

## Decision reads in Elixir

`Chronicle.ReadModels.DecisionReads` folds a read model at a key, in a fresh session, and
carries forward the exact event-log position the fold stopped at. `Chronicle.Transactions.UnitOfWork`
uses that position to guard a subsequent append: if anything else appends a matching event to the
guarded event source between the read and the commit, the kernel rejects the whole batch and
nothing is appended.

```elixir
Chronicle.decide(fn _unit_of_work ->
  {:ok, read} = Chronicle.ReadModels.DecisionReads.get(MyApp.ReadModels.Seat, "seat-5")

  if read.instance == nil do
    Chronicle.EventSequences.EventLog.append("seat-5", %SeatBooked{by: "alice"})
  end
end)
```

`Chronicle.decide/2` returns `{:ok, result}` when the commit succeeds, or
`{:error, %Chronicle.ReadModels.DecisionConflict{}}` when a decision read enrolled inside the
function conflicted with a concurrent append — the kernel rejected the commit, so nothing from
this attempt was written. Re-read and decide again:

```elixir
case Chronicle.decide(fn _unit_of_work ->
       {:ok, read} = Chronicle.ReadModels.DecisionReads.get(MyApp.ReadModels.Seat, "seat-5")
       if read.instance == nil, do: Chronicle.EventSequences.EventLog.append("seat-5", %SeatBooked{by: "alice"})
     end) do
  {:ok, _} -> :booked
  {:error, %Chronicle.ReadModels.DecisionConflict{}} -> :retry
  {:error, reason} -> {:error, reason}
end
```

To reject a decision, return `{:error, reason}` from the function. `Chronicle.decide/2` then
rolls the unit of work back, so nothing the function appended is written, even an append made
before the rejection, and returns `{:error, reason}` as-is. Any other return value is committed.
A commit that fails for another reason, such as an unreachable kernel, also rolls back and
returns `{:error, reason}`. Either way, once `Chronicle.decide/2` returns, its unit of work is
completed and its process stopped, so it is safe to call from a long-lived process such as a
GenServer or a Phoenix connection.

Call `get/2` only from inside `Chronicle.decide/2` (or `Chronicle.Transactions.UnitOfWork.with_unit_of_work/2`)
— it enrolls the read on the current unit of work. Call `get_detached/2` to fold the same way
without committing anything against it:

```elixir
{:ok, read} = Chronicle.ReadModels.DecisionReads.get_detached(MyApp.ReadModels.Seat, "seat-5")
read.instance
```

## Admission

Not every read model shape can be protected. `Chronicle.ReadModels.DecisionReads.admit/2` checks
a model's shape without any I/O, mirroring what `get/2` and `get_detached/2` check before folding:

```elixir
case Chronicle.ReadModels.DecisionReads.admit(MyApp.ReadModels.Seat) do
  {:ok, _event_types} -> :can_be_guarded
  {:error, reason} -> {:refused, reason}
end
```

A model with a `join/2`, `removed_with_join/2`, `children/2`, or `from_every/1` declaration is
refused — see `Chronicle.ReadModels.DecisionReadRefused` for every refusal reason. `get/2` and
`get_detached/2` raise that exception directly rather than returning the refusal as a value,
since a refused shape is a programming error to fix, not a runtime outcome to branch on.

## Guarding one event stream

Pass an event source id, event stream type, and event stream id directly to guard one stream
independently of the model's own key — useful when an event source definition routes the append
to a specific stream, such as a transaction log scoped to one month:

```elixir
{:ok, read} =
  Chronicle.ReadModels.DecisionReads.get_detached(
    MyApp.ReadModels.MonthlyWithdrawals,
    "account-1",
    "transactions",
    "2025-01"
  )
```

`admit_for_stream/2` checks the same shape `admit/2` does. The default stream (an empty or
`"All"` event stream type) is refused with `:all_streams_not_supported` — a stream-scoped guard
needs one specific stream.

## Guarding more than one event source

A rule that spans two entities needs one decision read per entity, because a decision read folds
one event source. Enroll both reads inside the same `Chronicle.decide/2` call and append one
event to each event source; the kernel admits or rejects the whole batch atomically:

```elixir
Chronicle.decide(fn _unit_of_work ->
  {:ok, course} = Chronicle.ReadModels.DecisionReads.get(MyApp.ReadModels.CourseSeats, course_id)
  {:ok, student} = Chronicle.ReadModels.DecisionReads.get(MyApp.ReadModels.StudentCourses, student_id)
  subscribed_courses = if student.instance, do: student.instance.subscribed, else: 0

  cond do
    course.instance == nil ->
      {:error, :unknown_course}

    course.instance.subscribed >= course.instance.capacity ->
      {:error, :course_is_full}

    subscribed_courses >= 5 ->
      {:error, :too_many_courses}

    true ->
      Chronicle.EventSequences.EventLog.append(course_id, %CourseSeatTaken{student_id: student_id})
      Chronicle.EventSequences.EventLog.append(student_id, %StudentJoinedCourse{course_id: course_id})
  end
end)
```

The `{:error, :course_is_full}` style rejections come back from `Chronicle.decide/2` unwrapped,
so match `{:error, :course_is_full}` rather than `{:ok, {:error, :course_is_full}}`. If either
side changed after it was read, the commit is rejected and neither event is appended.

## Passive reducers (Elixir-only)

The .NET client refuses a reducer-backed read model outright
(`DecisionReadRefusalReason.Reducer`). Elixir admits a **passive** reducer
(`use Chronicle.Reducers.Reducer, active: false`) instead: because a passive reducer's read
model is never kept warm by an observer, its current value is always folded fresh on the client
from the raw event log, which makes it trivial to capture the exact boundary the fold stopped at
without a kernel-side session. An **active** reducer is still refused with `:reducer` — nothing
outside the kernel knows when an actively-observed reducer reached a consistent point.

```elixir
defmodule MyApp.Reducers.SeatReducer do
  use Chronicle.Reducers.Reducer, model: MyApp.ReadModels.Seat, active: false

  @handles MyApp.Events.SeatBooked

  @impl true
  def reduce(%MyApp.Events.SeatBooked{by: by}, _model, _context), do: %MyApp.ReadModels.Seat{booked_by: by}
end
```

`Chronicle.ReadModels.DecisionReads.get/2` and `get_detached/2` work the same way against
`MyApp.ReadModels.Seat` whether it is backed by a projection or by this passive reducer.
