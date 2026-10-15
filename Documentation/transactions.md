---
sharedTopicBridge: true
---

# Transactions and Unit of Work

Unit-of-work transactions are now documented as a shared Chronicle workflow with synchronized client examples.

- [Transactions and unit of work](/chronicle/events/transactions/)
- [Appending many events](/chronicle/events/appending-many/)
- [Elixir client setup](./get-started.md)

## Guarding a commit with a decision read

`Chronicle.decide/2` runs a function inside a unit of work and commits it, same as
`Chronicle.Transactions.UnitOfWork.with_unit_of_work/2`, except a conflicting decision read never
raises: it returns `{:error, %Chronicle.ReadModels.DecisionConflict{}}` instead, so you can
re-read and retry the decision. Returning `{:error, reason}` from the function rolls the unit of
work back and returns `{:error, reason}`, so a rejected decision never writes. See
[Dynamic Consistency Boundary](./dynamic-consistency-boundary.md).

`Chronicle.decide/2` and `with_unit_of_work/2` own the unit of work they begin: when they return,
it is completed and its process stopped. A unit of work you start yourself with
`Chronicle.Transactions.UnitOfWork.begin/1` is yours to commit or roll back and to stop with
`Agent.stop/1`. After a failed `commit/1` it stays current until you retry or roll back.
