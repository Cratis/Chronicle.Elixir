```elixir
defmodule MyApp.ChronicleOptionsSqlSinkRegistration do
  @moduledoc false

  def start_link do
    children = [
      {Chronicle.Client, default_sink_type_id: :sql}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```
