```elixir
defmodule ReactorSideEffectsMultipleBookReserved do
  use Chronicle.Events.EventType, id: "reactor-side-effects-multiple-book-reserved"

  defstruct [:isbn]
end

defmodule ReactorSideEffectsMultipleStockDecreased do
  use Chronicle.Events.EventType, id: "reactor-side-effects-multiple-stock-decreased"

  defstruct [:isbn, :quantity]
end

defmodule ReactorSideEffectsMultipleStockLow do
  use Chronicle.Events.EventType, id: "reactor-side-effects-multiple-stock-low"

  defstruct [:isbn]
end

defmodule ReactorSideEffectsMultipleInventoryReactor do
  use Chronicle.Reactors.Reactor

  alias ReactorSideEffectsMultipleBookReserved
  alias ReactorSideEffectsMultipleStockDecreased
  alias ReactorSideEffectsMultipleStockLow

  @handles ReactorSideEffectsMultipleBookReserved

  # Returning a list of bare event structs appends all of them, atomically,
  # to the triggering event's own event source id.
  @impl true
  def handle(%ReactorSideEffectsMultipleBookReserved{} = event, _context) do
    {:ok,
     [
       %ReactorSideEffectsMultipleStockDecreased{isbn: event.isbn, quantity: 1},
       %ReactorSideEffectsMultipleStockLow{isbn: event.isbn}
     ]}
  end
end
```
