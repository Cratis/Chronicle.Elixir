```elixir
defmodule MyApp.Compliance.Erasure.AllowNewKey do
  def allow do
    Chronicle.Compliance.allow_new_encryption_key_for("person-42")
  end
end
```
