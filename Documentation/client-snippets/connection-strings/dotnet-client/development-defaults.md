```elixir
defmodule MyApp.ConnectionStringsDevelopmentDefaults do
  @moduledoc false

  def connection_string do
    Cratis.Chronicle.Connections.ConnectionString.default()
  end
end
```
