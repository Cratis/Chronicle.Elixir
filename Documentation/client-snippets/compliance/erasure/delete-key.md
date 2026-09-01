```elixir
defmodule MyApp.Compliance.Erasure.DeleteKey do
  def delete do
    Chronicle.Compliance.delete_encryption_key("person-42")
  end
end
```
