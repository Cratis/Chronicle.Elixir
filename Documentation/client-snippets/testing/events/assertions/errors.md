```elixir
defmodule MyApp.TestingAssertionsErrorsTest do
  # `{:error, {:append_errors, _}}` is the kernel reporting an append-level
  # error (as opposed to a constraint or concurrency violation) — for example a
  # malformed event payload the kernel rejects after the client's own schema
  # checks pass. `Chronicle.Testing.InMemoryKernel` does not model this failure
  # class yet, so this documents the match arm without exercising it; use
  # `Chronicle.Testing.Integration` against a real kernel to reproduce it.
  use ExUnit.Case, async: true
  @moduletag :skip

  test "append errors are reported as {:error, {:append_errors, errors}}" do
    result = {:error, {:append_errors, [%{Reason: "malformed-event"}]}}

    assert {:error, {:append_errors, errors}} = result
    assert length(errors) > 0
  end
end
```
