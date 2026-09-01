```elixir
defmodule MyApp.Events.CamelCasingUserRegistered do
  use Chronicle.Events.EventType, id: "camel-casing-user-registered"

  defstruct [:first_name, :last_name, :email_address, :registration_date]
end
```
