```elixir
defmodule MyApp.ChronicleOptionsConnectionStringRegistration do
  @moduledoc false

  def start_link do
    children = [
      {Cratis.Chronicle.Client, connection_string: "chronicle://myserver:35000"}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```
