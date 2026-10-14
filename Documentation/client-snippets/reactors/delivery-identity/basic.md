```elixir
defmodule IdempotentPaymentDue do
  use Chronicle.Events.EventType, id: "idempotent-payment-due"

  defstruct [:order_id, :amount]
end

defmodule IdempotentPaymentGateway do
  def charge(_order_id, _amount), do: :ok
end

# Your storage, not Chronicle's. One row per completed delivery, keyed by its identity.
defmodule IdempotentDeliveryReceipts do
  def completed?(_delivery_id), do: false
  def complete(_delivery_id), do: :ok
end

defmodule IdempotentBilling do
  use Chronicle.Reactors.Reactor

  @handles IdempotentPaymentDue

  @impl true
  def handle(%IdempotentPaymentDue{} = event, %{delivery_id: delivery_id}) do
    if IdempotentDeliveryReceipts.completed?(delivery_id) do
      :ok
    else
      with :ok <- IdempotentPaymentGateway.charge(event.order_id, event.amount) do
        IdempotentDeliveryReceipts.complete(delivery_id)
      end
    end
  end
end
```
