```elixir
# A concept is represented as the primitive it wraps: the schema Chronicle registers describes a
# string, and the value is written as a plain JSON string — `Jason.encode!(%PostalCode{value: "12345"})`
# is `"\"12345\""` — so the schema matches what is actually stored.
defmodule MyApp.Events.PostalCode do
  use Chronicle.Concept, type: :string
end

defmodule MyApp.Events.SchemaRepresentationAddressChanged do
  use Chronicle.Events.EventType, id: "schema-representation-address-changed"

  # The default is how the schema generator learns the field is a PostalCode.
  defstruct postal_code: %MyApp.Events.PostalCode{}
end
```
