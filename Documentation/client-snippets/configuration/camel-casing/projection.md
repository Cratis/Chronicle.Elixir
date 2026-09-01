```elixir
defmodule MyApp.Projections.CamelCasingUserProjection do
  use Chronicle.Projections.Projection, model: MyApp.ReadModels.CamelCasingUser

  from MyApp.Events.CamelCasingUserRegistered,
    set: [
      first_name: :first_name,
      last_name: :last_name,
      email_address: :email_address,
      registration_date: :registration_date
    ]
end
```
