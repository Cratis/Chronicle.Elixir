```elixir title="application.ex"
children = [
  {Chronicle.Client,
   connection_string: Chronicle.Connections.ConnectionString.development(),
   event_store: "chronicle-console",
   otp_app: :my_app}
]

Supervisor.start_link(children, strategy: :one_for_one)
```

```elixir title="Append the event"
alias Chronicle.Connections.Lifecycle

# The client registers in the background; appends return {:error, :not_connected} until then.
:ok = Lifecycle.wait_until(Lifecycle.name_for(Chronicle.Client), :registered)

:ok =
  Chronicle.append("some-event-source", %MyApp.Events.TestEvent{
    message: "Hello world!"
  })
```
