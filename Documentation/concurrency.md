---
title: Optimistic concurrency from Elixir
description: Guard Elixir appends with an expected sequence number and handle a conflict before deciding whether to retry.
sharedTopicBridge: true
---

Two requests can read the same account state and each decide that a withdrawal is allowed. If both append without a concurrency check, neither decision accounts for the other withdrawal. An optimistic concurrency scope lets you append only if the events your decision depends on have not changed.

Chronicle checks the expected tail sequence number against the current tail within that scope. If they differ, it rejects the append with a concurrency violation. The check does not lock the event source while your application makes its decision. See [Optimistic concurrency](/chronicle/events/concurrency/) for the shared concept and scope semantics.

## Guard an append

Use `Chronicle.Events.ConcurrencyScope.for_event_source/2` to check the event source you are appending to. Pass the resulting scope through the `:concurrency_scope` option to `Chronicle.append/3` or `Chronicle.append_many/3`.

This excerpt assumes a [configured client](get-started.md), an existing account, and a registered withdrawal event type. `account_id` identifies the account, `expected_tail` is the tail sequence number observed when loading the state used for the decision, and `withdrawal_event` is the event struct produced by that decision:

```elixir
alias Chronicle.Events.ConcurrencyScope

scope = ConcurrencyScope.for_event_source(expected_tail)

case Chronicle.append(account_id, withdrawal_event, concurrency_scope: scope) do
  :ok ->
    :ok

  {:error, {:concurrency_violations, violations}} ->
    {:error, {:concurrency_violations, violations}}

  {:error, reason} ->
    {:error, reason}
end
```

The append succeeds only if the scoped tail still matches `expected_tail`. A competing append outside the scope does not cause a conflict. The example returns conflicts to its caller rather than retrying them.

On a conflict, reload the state and reconsider the business decision before constructing another event. Do not just replace the expected sequence number and resend a withdrawal calculated from stale state. Other errors, including connection failures, remain separate from concurrency violations.

## Choose the scope and timing

The event source id comes from the append call, not from a string passed to `for_event_source/2`. Its optional keyword arguments can narrow the check by event types, event source type, stream type, or stream id. Keep that narrowing consistent with the events used to make your decision.

`ConcurrencyScope.at_tail/2` reads the current tail and returns a scope in one call. Read it before the decision it is meant to protect: fetching a fresh tail after deciding from older state leaves that earlier interval unchecked. For a creation-only operation, use `ConcurrencyScope.expecting_no_matching_event/1` to assert that no event matches the scope yet.

## Client defaults

By default, an append without an explicit or event-source-definition-derived scope sends no concurrency constraint. The `:concurrency` option on `Chronicle.Client` can enable automatic tail checks with `default: :optimistic`. An explicit or definition-derived scope takes precedence. This automatic check covers the interval between its tail lookup and the append, not an earlier application read.

With that strategy, `check_first_append: true` also guards the first append into an empty scope; the default is `false`. See [Event sequences](event-sequences.md#concurrency) for configuration, scope builders, and the restriction on unequal scopes for the same event source in a batch.
