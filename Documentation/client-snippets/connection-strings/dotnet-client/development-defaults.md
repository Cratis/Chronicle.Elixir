```elixir
defmodule MyApp.ConnectionStringsDevelopmentDefaults do
  @moduledoc false

  def connection_string do
    Chronicle.Connections.ConnectionString.default()
  end
end
```
