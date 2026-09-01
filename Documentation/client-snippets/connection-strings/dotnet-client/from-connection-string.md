```elixir
defmodule MyApp.ConnectionStringsFromConnectionString do
  @moduledoc false

  def start_link do
    children = [
      {Chronicle.Client, connection_string: "chronicle://localhost:35000"}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```
