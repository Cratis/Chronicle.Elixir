```elixir
defmodule MyApp.Events.TestSliceConstraintBookAdded do
  use Chronicle.Events.EventType, id: "test-slice-constraint-book-added"

  defstruct [:title, :isbn]

  unique(:isbn, name: "TestSliceConstraintUniqueIsbn")
end

defmodule MyApp.TestSliceConstraintTest do
  # Exercises the real client SDK against a running Chronicle event store,
  # so it's skipped here; remove the tag to run it against a live store.
  use ExUnit.Case, async: true
  @moduletag :skip

  alias MyApp.Events.TestSliceConstraintBookAdded

  test "adding a second book with an isbn already in use is rejected" do
    Chronicle.append(
      Base.encode16(:crypto.strong_rand_bytes(8), case: :lower),
      %TestSliceConstraintBookAdded{title: "The Pragmatic Programmer", isbn: "978-0135957059"}
    )

    result =
      Chronicle.append(
        Base.encode16(:crypto.strong_rand_bytes(8), case: :lower),
        %TestSliceConstraintBookAdded{
          title: "The Pragmatic Programmer, 2nd ed.",
          isbn: "978-0135957059"
        }
      )

    assert {:error, {:constraint_violations, violations}} = result

    assert Enum.any?(violations, fn violation ->
             Map.get(violation, :Name) == "TestSliceConstraintUniqueIsbn" or
               Map.get(violation, :name) == "TestSliceConstraintUniqueIsbn"
           end)
  end
end
```
