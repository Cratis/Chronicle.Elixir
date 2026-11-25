```elixir
defmodule MyApp.CorrelationIdentityCausationIdentity do
  alias Cratis.Chronicle.Identity

  def set_for_request(subject, name, user_name) do
    Cratis.Chronicle.set_identity(Identity.new(subject, name, user_name))
  end

  def get_current do
    Cratis.Chronicle.current_identity()
  end
end
```
