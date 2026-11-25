```elixir title="Custom key"
defmodule MyApp.Events.ConventionUserRegisteredWithKey do
  use Cratis.Chronicle.Events.EventType, id: "convention-user-registered-with-key-v1"

  defstruct [:user_id, :name, :email]
end

defmodule MyApp.ReadModels.ConventionUserById do
  use Cratis.Chronicle.ReadModels.ReadModel

  alias MyApp.Events.ConventionUserRegisteredWithKey

  defstruct [:name, :email]

  from ConventionUserRegisteredWithKey, key: :user_id
end
```
