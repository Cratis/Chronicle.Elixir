```elixir title="application.ex"
children = [
  {Cratis.Chronicle.Client,
   connection_string: Cratis.Chronicle.Connections.ConnectionString.development(),
   event_store: "chronicle-console",
   otp_app: :my_app}
]

Supervisor.start_link(children, strategy: :one_for_one)
```

```elixir title="Append the event"
alias Cratis.Chronicle.Connections.Lifecycle

# The client registers in the background; appends return {:error, :not_connected} until then.
:ok = Lifecycle.wait_until(Lifecycle.name_for(Cratis.Chronicle.Client), :registered)

:ok =
  Cratis.Chronicle.append("some-event-source", %MyApp.Events.TestEvent{
    message: "Hello world!"
  })
```
