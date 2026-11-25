```elixir
defmodule MyApp.Events.TestingAssertionsConcurrencyAccountOpened do
  use Cratis.Chronicle.Events.EventType, id: "testing-assertions-concurrency-account-opened"

  defstruct [:account_name]
end

defmodule MyApp.TestingAssertionsConcurrencyTest do
  use ExUnit.Case, async: true

  import Cratis.Chronicle.Testing.Assertions

  alias Cratis.Chronicle.Events.ConcurrencyScope
  alias MyApp.Events.TestingAssertionsConcurrencyAccountOpened

  test "a second first-append for the same account is a concurrency violation" do
    {:ok, client} =
      Cratis.Chronicle.Testing.start_supervised_client(
        event_types: [TestingAssertionsConcurrencyAccountOpened]
      )

    on_exit(fn -> Cratis.Chronicle.Testing.stop_supervised_client(client) end)

    account_id = "account-#{System.unique_integer([:positive])}"
    scope = ConcurrencyScope.expecting_no_matching_event(event_source_id: true)

    :ok =
      Cratis.Chronicle.EventSequences.EventLog.append(
        account_id,
        %TestingAssertionsConcurrencyAccountOpened{account_name: "Ada"},
        client: client,
        concurrency_scope: scope
      )

    result =
      Cratis.Chronicle.EventSequences.EventLog.append(
        account_id,
        %TestingAssertionsConcurrencyAccountOpened{account_name: "Ada"},
        client: client,
        concurrency_scope: scope
      )

    assert_concurrency_violation(result)
  end
end
```
