```elixir
defmodule MyApp.Events.ConcurrencyFirstAppendAccountOpened do
  use Chronicle.Events.EventType, id: "concurrency-first-append-account-opened"

  defstruct account_name: ""
end

defmodule MyApp.ConcurrencyFirstAppendAccountService do
  alias Chronicle.Events.ConcurrencyScope
  alias MyApp.Events.ConcurrencyFirstAppendAccountOpened

  # Per append: ask for the check on one behavior without changing the client's default.
  def open_account(account_id, account_name) do
    scope =
      ConcurrencyScope.expecting_no_matching_event(
        event_source_id: true,
        event_types: [ConcurrencyFirstAppendAccountOpened]
      )

    Chronicle.append(
      account_id,
      %ConcurrencyFirstAppendAccountOpened{account_name: account_name},
      concurrency_scope: scope
    )
  end
end
```

Application-wide, opt every first append into an empty narrowing into the same check through
the client's `:concurrency` option:

```elixir
{Chronicle.Client,
  connection_string: "chronicle://localhost:35000",
  event_store: "my-store",
  concurrency: [default: :optimistic, check_first_append: true]}
```
