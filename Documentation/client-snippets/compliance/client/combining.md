```elixir
defmodule MyApp.Compliance.Client.CombiningPersonName do
  use Cratis.Chronicle.Concept, type: :string
  pii()
end

defmodule MyApp.Compliance.Client.CombiningEmailAddress do
  use Cratis.Chronicle.Concept, type: :string
  pii()
end

defmodule MyApp.Compliance.Client.CustomerRegistered do
  use Cratis.Chronicle.Events.EventType, id: "compliance-client-customer-registered"

  defstruct name: %MyApp.Compliance.Client.CombiningPersonName{},
            email: %MyApp.Compliance.Client.CombiningEmailAddress{},
            phone_number: "",
            country: ""

  # name and email are encrypted via their concept types; phone_number is
  # encrypted via this property-level annotation; country stays plaintext.
  pii(:phone_number)
end
```
