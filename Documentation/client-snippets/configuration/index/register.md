```elixir
defmodule MyApp.ConfigurationIndexRegistration do
  @moduledoc false

  def start_link do
    children = [
      {Chronicle.Client, event_store: "my-store"}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```
