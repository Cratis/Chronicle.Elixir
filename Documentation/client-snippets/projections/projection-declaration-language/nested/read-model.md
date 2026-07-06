```elixir
defmodule MyApp.ReadModels.PdlCommandItem do
  defstruct name: "", schema: ""
end

defmodule MyApp.ReadModels.PdlSliceReadModel do
  # command is nil until set
  defstruct name: "", command: nil
end
```
