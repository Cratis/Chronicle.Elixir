```elixir
defmodule MyApp.Events.IdempotencyOrderPlaced do
  use Chronicle.Events.EventType, id: "idempotency-order-placed"

  defstruct [:customer, :idempotency_token]

  unique(:idempotency_token)
end

defmodule MyApp.IdempotencyPlaceOrder do
  alias Chronicle.EventSequences.EventLog
  alias MyApp.Events.IdempotencyOrderPlaced

  # The caller generates the token once per order and sends the same token on every retry.
  # The order's event source id is generated here, so a retry is a different source with the same token.
  def handle(customer, idempotency_token) do
    order_id = Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)

    event = %IdempotencyOrderPlaced{customer: customer, idempotency_token: idempotency_token}

    case EventLog.append_with_result(order_id, event) do
      {:ok, _result} -> :placed
      {:error, %{constraint_violations: [_ | _]}} -> :already_placed
      {:error, _result} -> :failed
    end
  end
end
```
