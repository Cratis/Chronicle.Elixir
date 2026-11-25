```elixir
defmodule MyApp.CorrelationIdentityCausationCorrelation do
  alias Cratis.Chronicle.Correlation.CorrelationId

  def get_current do
    Cratis.Chronicle.current_correlation_id()
  end

  def set_for_request do
    Cratis.Chronicle.set_correlation_id(CorrelationId.create())
  end
end
```
