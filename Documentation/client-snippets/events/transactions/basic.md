```elixir
defmodule MyApp.Events.TransactionalOrderPlaced do
  use Chronicle.Events.EventType, id: "TransactionalOrderPlaced"

  defstruct [:order_id, :total_amount]
end

defmodule MyApp.Events.TransactionalInventoryReserved do
  use Chronicle.Events.EventType, id: "TransactionalInventoryReserved"

  defstruct [:sku, :quantity]
end

defmodule MyApp.TransactionalOrderWorkflow do
  alias Chronicle.Transactions.UnitOfWork
  alias MyApp.Events.{TransactionalInventoryReserved, TransactionalOrderPlaced}

  def commit_order do
    unit_of_work = UnitOfWork.begin()

    try do
      :ok =
        Chronicle.append("order-123", %TransactionalOrderPlaced{
          order_id: "order-123",
          total_amount: 99.95
        })

      :ok =
        Chronicle.append("inventory-widget", %TransactionalInventoryReserved{
          sku: "widget",
          quantity: 1
        })

      :ok = UnitOfWork.commit(unit_of_work)
    rescue
      exception ->
        UnitOfWork.rollback(unit_of_work)
        reraise exception, __STACKTRACE__
    end
  end
end
```
