```elixir
defmodule MyApp.Events.ScenariosReactReturnBookReserved do
  use Chronicle.Events.EventType, id: "scenarios-react-return-book-reserved"

  defstruct [:isbn]
end

defmodule MyApp.Events.ScenariosReactReturnStockDecreased do
  use Chronicle.Events.EventType, id: "scenarios-react-return-stock-decreased"

  defstruct [:isbn, :quantity]
end

defmodule MyApp.Reactors.ScenariosReactReturnStockKeeping do
  # Without `once_only`, a replay of this reactor appends StockDecreased again.
  use Chronicle.Reactors.Reactor,
    once_only: [MyApp.Events.ScenariosReactReturnBookReserved]

  alias MyApp.Events.{ScenariosReactReturnBookReserved, ScenariosReactReturnStockDecreased}

  @handles ScenariosReactReturnBookReserved

  # The returned event is appended to the same event source as a side effect.
  @impl true
  def handle(%ScenariosReactReturnBookReserved{isbn: isbn}, _context) do
    {:ok, %ScenariosReactReturnStockDecreased{isbn: isbn, quantity: 1}}
  end
end
```
