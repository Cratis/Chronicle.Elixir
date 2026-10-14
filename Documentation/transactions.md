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
re-read and retry the decision. See [Dynamic Consistency Boundary](./dynamic-consistency-boundary.md).
