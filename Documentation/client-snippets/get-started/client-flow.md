```elixir title="application.ex"
children = [
  {Chronicle.Client,
   connection_string: "chronicle://localhost:35000",
   event_store: "chronicle-console",
   otp_app: :my_app}
]

Supervisor.start_link(children, strategy: :one_for_one)
```

```elixir title="Append the event"
:ok =
  Chronicle.append("some-event-source", %MyApp.Events.TestEvent{
    message: "Hello world!"
  })
```
