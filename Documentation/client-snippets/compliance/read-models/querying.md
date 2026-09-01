```elixir
defmodule MyApp.Compliance.ReadModels.QueryingPersonName do
  use Chronicle.Concept, type: :string
  pii()
end

defmodule MyApp.Compliance.ReadModels.QueryingEmployee do
  use Chronicle.ReadModels.ReadModel

  defstruct id: nil, name: %MyApp.Compliance.ReadModels.QueryingPersonName{}, department: nil
end

defmodule MyApp.Compliance.ReadModels.EmployeeService do
  # PII decryption is transparent here — the caller just gets the plain,
  # decrypted value back.
  def get_employee(id) do
    Chronicle.ReadModels.get(MyApp.Compliance.ReadModels.QueryingEmployee, id)
  end
end
```
