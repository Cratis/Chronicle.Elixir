```elixir
defmodule MyApp.CorrelationIdentityCausationCorrelation do
  alias Chronicle.CorrelationId

  def get_current do
    Chronicle.current_correlation_id()
  end

  def set_for_request do
    Chronicle.set_correlation_id(CorrelationId.create())
  end
end
```
