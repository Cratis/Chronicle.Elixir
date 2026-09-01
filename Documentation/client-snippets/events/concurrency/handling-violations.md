```elixir
defmodule MyApp.Events.ConcurrencySafeAccountOpened do
  use Chronicle.Events.EventType, id: "concurrency-safe-account-opened"

  defstruct [:account_name]
end

defmodule MyApp.ConcurrencySafeAccountService do
  alias Chronicle.EventSequences.EventLog
  alias Chronicle.Events.ConcurrencyScope
  alias MyApp.Events.ConcurrencySafeAccountOpened

  def try_open_account(account_id, account_name) do
    with {:ok, tail} <- EventLog.get_tail_sequence_number(account_id) do
      # Expect no event for this account yet
      scope = ConcurrencyScope.for_event_source(tail)

      case Chronicle.append(
             account_id,
             %ConcurrencySafeAccountOpened{account_name: account_name},
             concurrency_scope: scope
           ) do
        :ok ->
          true

        {:error, {:append_errors, _errors}} ->
          # A concurrency violation surfaces as an append error — retry against
          # the state the winner produced, or surface the conflict.
          false

        {:error, _reason} ->
          false
      end
    end
  end
end
```
