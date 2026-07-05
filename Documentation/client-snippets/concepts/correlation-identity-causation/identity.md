```elixir
defmodule MyApp.CorrelationIdentityCausationIdentity do
  alias Chronicle.Identity

  def set_for_request(subject, name, user_name) do
    Chronicle.set_identity(Identity.new(subject, name, user_name))
  end

  def get_current do
    Chronicle.current_identity()
  end
end
```
