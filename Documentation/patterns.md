---
title: Behavior patterns
description: Ask what a scope usually does, using the behavior patterns Chronicle mined from the event history of an event store.
---

`Chronicle.Patterns` provides an idiomatic Elixir API over the behavior patterns Chronicle mines from the event history of an event store — recurring combinations of facets (`Day`, `TimeBucket`, `CommandType`, `AggregateType`, and so on) that survived its support and confidence thresholds.

An empty result from any of these functions is an answer, not a failure: it says the scope has no established behavior for the asked context. Nothing is invented to fill the gap, so a caller can treat "no patterns" as "do not claim to know".

## Asking about a moment

The question an application actually has is usually "what does this person usually do right now" — not an arbitrary facet combination. `get_patterns_at/3` is that question:

```elixir
{:ok, patterns} = Chronicle.Patterns.get_patterns_at("user-42")
```

`Day` and `TimeBucket` are derived from the moment using its own offset, not UTC, with the same rule the kernel used when it mined the patterns — a scope's established morning behavior is asked about in their own morning, wherever they are. The moment defaults to now; pass one explicitly to ask about a different time:

```elixir
{:ok, patterns} = Chronicle.Patterns.get_patterns_at("user-42", tomorrow_morning)
```

Narrow the question with more of the situation using `:also_constraining` — asking about a moment and asking about a kind of work are the same call rather than two competing ones:

```elixir
{:ok, patterns} =
  Chronicle.Patterns.get_patterns_at(
    "user-42",
    nil,
    also_constraining: %{Chronicle.Patterns.FacetName.aggregate_type() => "Invoice"}
  )
```

A result names the action it answers for through `Chronicle.Patterns.FacetName.command_type()`:

```elixir
action = pattern.facets[Chronicle.Patterns.FacetName.command_type()]
```

## The low-level facet-set query

`get_patterns_at/3` is a wrapper, not a replacement — `get_patterns/3` and `get_usual_actions/3` stay available for a context built by hand:

```elixir
context = %{
  Chronicle.Patterns.FacetName.day() => "Monday",
  Chronicle.Patterns.FacetName.time_bucket() => "Morning"
}

{:ok, patterns} = Chronicle.Patterns.get_patterns("user-42", context)
{:ok, actions} = Chronicle.Patterns.get_usual_actions("user-42", context)
```

`get_patterns/3` returns patterns that describe a situation; `get_usual_actions/3` returns the ones that say what is done in it, at most one answer per action.

## Inspecting what has been mined

```elixir
{:ok, patterns} = Chronicle.Patterns.get_patterns_for_scope("user-42")
{:ok, scopes} = Chronicle.Patterns.get_scopes()
```

## The time bucket rule

`Chronicle.Patterns.time_bucket/1` exposes the same part-of-day rule the kernel mined with, so an application never writes its own copy of it — getting it wrong means asking about a slot the mining never used, which looks exactly like "nothing is established here":

| Hours | Bucket |
| --- | --- |
| 05:00–08:00 | `:early_morning` |
| 08:00–11:00 | `:morning` |
| 11:00–14:00 | `:midday` |
| 14:00–17:00 | `:afternoon` |
| 17:00–22:00 | `:evening` |
| 22:00–05:00 | `:night` |

```elixir
Chronicle.Patterns.time_bucket(DateTime.utc_now())
```

## Options

Every function accepts:

- `:client` — the client name (default: `Chronicle.Client`)
- `:namespace` — overrides the client's configured namespace
- `:minimum_confidence` — the lowest confidence (`0.0`–`1.0`) an answer may hold; defaults to the server's configured threshold
- `:max_results` — the largest number of answers to return; defaults to the server's default

## Not supported

`AllPatterns` (every mined pattern for an event store, regardless of scope) is not exposed, matching the .NET client's `IPatterns`.
