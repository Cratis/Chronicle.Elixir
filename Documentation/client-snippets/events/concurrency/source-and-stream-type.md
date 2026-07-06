```elixir
defmodule MyApp.Events.ConcurrencyAccountSettingsUpdated do
  use Chronicle.Events.EventType, id: "concurrency-account-settings-updated"

  defstruct [:settings]
end

defmodule MyApp.ConcurrencyAccountManagementService do
  alias Chronicle.Events.ConcurrencyScope
  alias MyApp.Events.ConcurrencyAccountSettingsUpdated

  def update_account_settings(account_id, settings) do
    scope =
      ConcurrencyScope.for_event_source(10,
        event_source_type: "BankAccount",
        event_stream_type: "AccountManagement"
      )

    Chronicle.append(
      account_id,
      %ConcurrencyAccountSettingsUpdated{settings: settings},
      event_source_type: "BankAccount",
      event_stream_type: "AccountManagement",
      concurrency_scope: scope
    )
  end
end
```
