```elixir
defmodule MyApp.Events.ConcurrencySafeAccountOpened do
  use Chronicle.Events.EventType, id: "concurrency-safe-account-opened"

  defstruct account_name: ""
end

defmodule MyApp.ConcurrencySafeAccountService do
  alias Chronicle.Events.ConcurrencyScope
  alias MyApp.Events.ConcurrencySafeAccountOpened

  def try_open_account(account_id, account_name) do
    # Expect no event for this account yet
    scope = ConcurrencyScope.expecting_no_matching_event(event_source_id: true)

    case Chronicle.append(
           account_id,
           %ConcurrencySafeAccountOpened{account_name: account_name},
           concurrency_scope: scope
         ) do
      :ok ->
        true

      {:error, {:concurrency_violations, _violations}} ->
        # Another append got there first — retry against the state the winner
        # produced, or surface the conflict.
        false

      {:error, _reason} ->
        false
    end
  end
end
```
