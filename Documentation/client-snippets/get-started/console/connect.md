```elixir title="application.ex"
defmodule MyApp.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Chronicle.Client,
       connection_string: "chronicle://localhost:35000?disableTls=true",
       event_store: "quickstart",
       otp_app: :my_app}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: MyApp.Supervisor)
  end
end
```

```elixir title="Confirm the connection"
{:ok, event_stores} = Chronicle.get_event_stores()
IO.puts("Connected to event store: #{Enum.at(event_stores, 0)}")

# Use Chronicle.* functions for the lifetime of your program — appending, querying, and so on.
```
