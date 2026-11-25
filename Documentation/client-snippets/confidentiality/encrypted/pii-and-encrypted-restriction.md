```elixir
# Raises Cratis.Chronicle.Confidentiality.PiiAndEncryptedCombinedNotSupported at
# schema-generation time.
#
# defmodule MyApp.Events.EncryptedAttrCustomerRegistered do
#   use Cratis.Chronicle.Events.EventType, id: "encrypted-attr-customer-registered"
#   defstruct [:some_value]
#
#   pii(:some_value)
#   encrypted(:some_value)
# end
```
