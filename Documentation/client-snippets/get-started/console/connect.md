```elixir title="application.ex"
defmodule MyApp.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Cratis.Chronicle.Client,
       # The local development kernel's well-known credentials.
       connection_string: Cratis.Chronicle.Connections.ConnectionString.development(),
       event_store: "quickstart",
       otp_app: :my_app}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: MyApp.Supervisor)
  end
end
```

```elixir title="Confirm the connection"
alias Cratis.Chronicle.Connections.Lifecycle

# Wait until the client has connected and registered its event types and read models.
:ok = Lifecycle.wait_until(Lifecycle.name_for(Cratis.Chronicle.Client), :registered)

{:ok, event_stores} = Cratis.Chronicle.get_event_stores()
IO.puts("Event stores: #{Enum.join(event_stores, ", ")}")

# Use Chronicle.* functions for the lifetime of your program — appending, querying, and so on.
```
