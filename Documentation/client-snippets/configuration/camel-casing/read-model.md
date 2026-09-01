```elixir
defmodule MyApp.ReadModels.CamelCasingUser do
  use Chronicle.ReadModels.ReadModel

  defstruct first_name: nil, last_name: nil, email_address: nil, registration_date: nil
end
```
