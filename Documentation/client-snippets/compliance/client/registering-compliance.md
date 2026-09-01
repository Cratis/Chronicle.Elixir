```elixir
# No separate compliance registration step exists. Compliance metadata is
# resolved automatically — from pii/1,2 declarations and from
# Chronicle.Concept field types — whenever an event type or read model is
# registered, as part of the normal Chronicle.Client supervision tree entry.
{Chronicle.Client,
  connection_string: "chronicle://localhost:35000",
  event_store: "my-store",
  event_types: [MyApp.Compliance.Client.CustomerRegistered],
  read_models: [MyApp.Compliance.Client.Customer]}
```
