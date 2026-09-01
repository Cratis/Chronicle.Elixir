```elixir
defmodule MyApp.ConnectionStringsDevelopmentDefaultsEquivalent do
  @moduledoc false

  def connection_string do
    Chronicle.Connections.ConnectionString.parse("chronicle://localhost:35000")
  end
end
```
