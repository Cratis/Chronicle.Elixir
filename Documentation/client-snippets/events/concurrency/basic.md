```elixir
defmodule MyApp.Events.ConcurrencyAccountOpened do
  use Chronicle.Events.EventType, id: "concurrency-account-opened"

  defstruct [:account_name]
end

defmodule MyApp.ConcurrencyBankAccountService do
  alias Chronicle.Events.ConcurrencyScope
  alias MyApp.Events.ConcurrencyAccountOpened

  def open_account(account_id, account_name) do
    scope = ConcurrencyScope.for_event_source(42)

    Chronicle.append(account_id, %ConcurrencyAccountOpened{account_name: account_name},
      concurrency_scope: scope
    )
  end
end
```
