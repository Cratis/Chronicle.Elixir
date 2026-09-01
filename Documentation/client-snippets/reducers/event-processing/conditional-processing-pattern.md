```elixir
defmodule EventProcessingAccountOpened do
  use Chronicle.Events.EventType, id: "event-processing-account-opened"

  defstruct [:account_id]
end

defmodule EventProcessingDepositMade do
  use Chronicle.Events.EventType, id: "event-processing-deposit-made"

  defstruct [:amount]
end

defmodule EventProcessingAccountClosed do
  use Chronicle.Events.EventType, id: "event-processing-account-closed"

  defstruct []
end

defmodule EventProcessingAccount do
  defstruct [:account_id, :balance, :is_active]
end

defmodule EventProcessingAccountReducer do
  use Chronicle.Reducers.Reducer, model: EventProcessingAccount

  alias EventProcessingAccountOpened
  alias EventProcessingDepositMade
  alias EventProcessingAccountClosed

  @handles EventProcessingAccountOpened
  @handles EventProcessingDepositMade
  @handles EventProcessingAccountClosed

  @impl true
  def reduce(%EventProcessingAccountOpened{} = event, _current, _context) do
    %EventProcessingAccount{account_id: event.account_id, balance: 0, is_active: true}
  end

  # Skip if the account doesn't exist or is no longer active
  def reduce(%EventProcessingDepositMade{}, nil, _context), do: nil
  def reduce(%EventProcessingDepositMade{}, %{is_active: false} = current, _context), do: current

  def reduce(%EventProcessingDepositMade{} = event, current, _context) do
    %{current | balance: current.balance + event.amount}
  end

  def reduce(%EventProcessingAccountClosed{}, nil, _context), do: nil
  def reduce(%EventProcessingAccountClosed{}, current, _context), do: %{current | is_active: false}
end
```
