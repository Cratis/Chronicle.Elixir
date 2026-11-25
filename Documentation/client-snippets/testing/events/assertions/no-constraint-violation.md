```elixir
defmodule MyApp.Events.TestingAssertionsNoViolationAuthorRegistered do
  use Cratis.Chronicle.Events.EventType, id: "testing-assertions-no-violation-author-registered"

  defstruct [:name]
end

defmodule MyApp.TestingAssertionsNoConstraintViolationTest do
  use ExUnit.Case, async: true

  alias MyApp.Events.TestingAssertionsNoViolationAuthorRegistered

  test "appending two different names does not violate a constraint" do
    {:ok, client} =
      Cratis.Chronicle.Testing.start_supervised_client(
        event_types: [TestingAssertionsNoViolationAuthorRegistered]
      )

    on_exit(fn -> Cratis.Chronicle.Testing.stop_supervised_client(client) end)

    result =
      Cratis.Chronicle.EventSequences.EventLog.append(
        "author-#{System.unique_integer([:positive])}",
        %TestingAssertionsNoViolationAuthorRegistered{name: "Jane Smith"},
        client: client
      )

    assert result == :ok
  end
end
```
