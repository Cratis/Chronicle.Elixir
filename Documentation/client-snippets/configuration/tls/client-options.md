```elixir
defmodule MyApp.TlsClientOptions do
  @moduledoc false

  def start_link do
    children = [
      {Chronicle.Client,
       connection_string:
         "chronicle://localhost:35000?certificatePath=/path/to/certificate.pfx&certificatePassword=your-password"}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```
