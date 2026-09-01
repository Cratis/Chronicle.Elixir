```elixir
defmodule MyApp.Compliance.Pii.DateOfBirth do
  use Chronicle.Concept, type: :string
  pii()
end

# The concept sits one level down, inside a plain (non-concept) value object.
defmodule MyApp.Compliance.Pii.VerifiedDateOfBirth do
  defstruct date_of_birth: %MyApp.Compliance.Pii.DateOfBirth{}, verified_by: ""
end

# Chronicle still finds it: dateOfBirth.dateOfBirth is encrypted, verifiedBy is not.
defmodule MyApp.Compliance.Pii.ExpressVerification do
  use Chronicle.Events.EventType, id: "pii-express-verification"
  defstruct name: "", date_of_birth: %MyApp.Compliance.Pii.VerifiedDateOfBirth{}
end
```
