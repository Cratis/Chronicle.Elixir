```elixir
defmodule MyApp.Concepts.TestingAssertionsEmail do
  use Cratis.Chronicle.Concept, type: :string
end

defmodule MyApp.Events.TestingAssertionsAuthorRegisteredWithEmail do
  use Cratis.Chronicle.Events.EventType, id: "testing-assertions-author-registered-with-email"

  unique(:email, name: "TestingAssertionsUniqueAuthorEmail")

  defstruct email: %MyApp.Concepts.TestingAssertionsEmail{}
end

defmodule MyApp.TestingAssertionsConstraintE2eTest do
  use ExUnit.Case, async: true

  import Cratis.Chronicle.Testing.Assertions

  alias MyApp.Concepts.TestingAssertionsEmail
  alias MyApp.Events.TestingAssertionsAuthorRegisteredWithEmail

  test "registering an author with a taken email is rejected" do
    {:ok, client} =
      Cratis.Chronicle.Testing.start_supervised_client(
        event_types: [TestingAssertionsAuthorRegisteredWithEmail]
      )

    on_exit(fn -> Cratis.Chronicle.Testing.stop_supervised_client(client) end)

    email = %TestingAssertionsEmail{value: "john@doe.com"}

    :ok =
      Cratis.Chronicle.EventSequences.EventLog.append(
        "author-#{System.unique_integer([:positive])}",
        %TestingAssertionsAuthorRegisteredWithEmail{email: email},
        client: client
      )

    result =
      Cratis.Chronicle.EventSequences.EventLog.append(
        "author-#{System.unique_integer([:positive])}",
        %TestingAssertionsAuthorRegisteredWithEmail{email: email},
        client: client
      )

    assert_constraint_violation(result, "TestingAssertionsUniqueAuthorEmail")
  end
end
```
