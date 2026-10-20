---
title: Plan seed data
description: Decide which baseline events your Elixir application needs before implementing a Chronicle seeder.
---

A fresh event store may need reference data before the application can handle its first request. Decide which facts belong in that baseline before writing a seeder. Keep user-driven changes in the application's normal append flow rather than treating them as startup data.

## Before implementing a seeder

- Identify the event types and event source ids the application needs at startup. Keep the list small enough to review.
- Use fixed ids and deterministic event content rather than generating different data each time the client starts.
- Separate data shared by tenants from data that belongs to a specific namespace. Make that choice explicit in the seeder.
- Plan corrections as new events. Seeding is not a migration script for rewriting events already stored.

The shared [Event seeding](/chronicle/event-seeding/) page explains the Chronicle behavior. Continue with [Implement seeding in Elixir](../seeding.md) for event definitions, seeder registration, namespace-scoped data, and retry behavior. If you have not connected a client yet, start with [Elixir client setup](../get-started.md).
