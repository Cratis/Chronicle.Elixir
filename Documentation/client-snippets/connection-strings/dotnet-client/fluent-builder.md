```elixir title="Build a connection string step by step"
defmodule MyApp.ConnectionStringsFluentBuilder do
  @moduledoc false

  alias Chronicle.Connections.ConnectionString

  def connection_string do
    "chronicle://server.example.com:35000"
    |> ConnectionString.parse()
    |> ConnectionString.with_credentials("clientId", "clientSecret")
    |> ConnectionString.format()
  end

  def start_link do
    children = [
      {Chronicle.Client, connection_string: connection_string()}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```
