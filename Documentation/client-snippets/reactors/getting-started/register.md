```elixir
defmodule MyApp.ReactorClientConfig do
  def child_spec do
    {Chronicle.Client,
     connection_string: "chronicle://localhost:35000?disableTls=true",
     event_store: "store",
     reactors: [MyApp.Reactors.OrderNotificationsReactor]}
  end
end
```
