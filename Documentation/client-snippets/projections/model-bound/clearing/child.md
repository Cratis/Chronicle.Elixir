```elixir
defmodule MyApp.Events.MbClearingChildItemAdded do
  use Chronicle.Events.EventType, id: "mb-clearing-child-item-added"

  defstruct [:item_id, :note]
end

defmodule MyApp.Events.MbClearingChildItemNoteCleared do
  use Chronicle.Events.EventType, id: "mb-clearing-child-item-note-cleared"

  defstruct [:item_id]
end

defmodule MyApp.ReadModels.MbClearingChildItem do
  defstruct item_id: nil, note: nil
end

defmodule MyApp.ReadModels.MbClearingChildBasket do
  use Chronicle.ReadModels.ReadModel,
    types: [items: {:list, MyApp.ReadModels.MbClearingChildItem}]

  defstruct basket_id: nil, items: []

  children :items, identified_by: :item_id do
    from MyApp.Events.MbClearingChildItemAdded,
      key: :item_id,
      set: [item_id: :item_id, note: :note]

    # The clearing event has to reach the child through the same `children` block the child's
    # own `from` is declared in, with the key that identifies which item to clear.
    clear_with MyApp.Events.MbClearingChildItemNoteCleared, [:note], key: :item_id
  end
end
```
