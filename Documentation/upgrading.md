---
title: Upgrading to 4.0
description: Upgrade the Chronicle Elixir client to 4.0 by renaming module references to Cratis.Chronicle. The Hex package and stored events are unchanged.
---

Version 4.0 moves every module from `Chronicle` to `Cratis.Chronicle`, so the client sits in the same vendor namespace as the other Cratis packages and cannot collide with another library that defines a top-level `Chronicle` module.

## What to rename

Replace `Chronicle.` with `Cratis.Chronicle.` wherever you refer to a module of the client:

```elixir
# Before
use Chronicle.Events.EventType, id: "author-registered"
{:ok, authors} = Chronicle.all(MyApp.Authors.Author)

# After
use Cratis.Chronicle.Events.EventType, id: "author-registered"
{:ok, authors} = Cratis.Chronicle.all(MyApp.Authors.Author)
```

That covers `use`, `alias`, `import`, `@behaviour`, type specs and function calls, including the testing helpers such as `Chronicle.Testing`. A search and replace of `Chronicle.` with `Cratis.Chronicle.` on your own code is enough; the sources of the client moved from `lib/chronicle` to `lib/cratis/chronicle`.

## What stays the same

- The Hex package and OTP application: `{:cratis_chronicle, "~> 4.0"}` and `:cratis_chronicle`, including every `config :cratis_chronicle` key.
- Mix tasks (`mix chronicle.install`, `mix chronicle.discover`) and the `:chronicle` Mix compiler.
- Telemetry event names (`[:chronicle, ...]`), the OpenTelemetry scope `Cratis.Chronicle.Client`, and everything on the wire. Event type ids, observer ids and read model names are unchanged, so stored events and registered observers keep working without a migration.
- Your own modules. Defaults that derive from a module name, such as a capture or seeder id, use *your* module's name, which you did not rename.
