```elixir
defmodule MyApp.Events.ReactorAccountClosed do
  use Chronicle.Events.EventType, id: "reactor-account-closed"

  defstruct [:account_id]
end

defmodule MyApp.Reactors.AuditReactor do
  use Chronicle.Reactors.Reactor

  alias MyApp.Events.ReactorAccountClosed

  @handles ReactorAccountClosed

  @impl true
  def handle(%ReactorAccountClosed{} = event, context) do
    write_audit(event.account_id, Map.get(context, :occurred), Map.get(context, :event_source_id))

    :ok
  end

  defp write_audit(_account_id, _occurred, _event_source_id), do: :ok
end
```
