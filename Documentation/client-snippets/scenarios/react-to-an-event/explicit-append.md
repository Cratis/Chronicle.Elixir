```elixir
defmodule MyApp.Events.ScenariosReactBookReserved do
  use Chronicle.Events.EventType, id: "scenarios-react-book-reserved"

  defstruct [:isbn]
end

defmodule MyApp.Events.ScenariosReactStockDecreased do
  use Chronicle.Events.EventType, id: "scenarios-react-stock-decreased"

  defstruct [:isbn, :quantity]
end

defmodule MyApp.ScenariosReactStockCouldNotBeDecreased do
  defexception [:message]

  def exception(isbn) do
    %__MODULE__{message: "Stock could not be decreased for ISBN #{isbn}"}
  end
end

defmodule MyApp.Reactors.ScenariosReactStockKeepingExplicit do
  use Chronicle.Reactors.Reactor

  alias MyApp.Events.{ScenariosReactBookReserved, ScenariosReactStockDecreased}
  alias MyApp.ScenariosReactStockCouldNotBeDecreased

  @handles ScenariosReactBookReserved

  @impl true
  def handle(%ScenariosReactBookReserved{isbn: isbn}, %{event_source_id: event_source_id}) do
    case Chronicle.append(event_source_id, %ScenariosReactStockDecreased{isbn: isbn, quantity: 1}) do
      :ok -> :ok
      {:error, _reason} -> raise ScenariosReactStockCouldNotBeDecreased, isbn
    end
  end
end
```
