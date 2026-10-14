# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

# Round trip against a real kernel (19.56.0 or newer). Opt in by pointing
# CHRONICLE_INTEGRATION_CONNECTION_STRING at a development kernel, for example
# chronicle://chronicle-dev-client:chronicle-dev-secret@localhost:35000
# and run `mix test --include integration`.
defmodule Chronicle.Integration.PatternsTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  alias Chronicle.Patterns

  setup_all do
    prefix = System.get_env("CHRONICLE_INTEGRATION_EVENT_STORE_PREFIX", "patterns-elixir")

    {:ok, _} =
      Chronicle.Client.start_link(
        name: :patterns_it_client,
        connection_string: System.fetch_env!("CHRONICLE_INTEGRATION_CONNECTION_STRING"),
        event_store:
          "#{prefix}-#{System.system_time(:millisecond)}-#{System.unique_integer([:positive])}",
        discover: false
      )

    lifecycle = Chronicle.Connections.Lifecycle.name_for(:patterns_it_client)
    :ok = Chronicle.Connections.Lifecycle.wait_until(lifecycle, :registered, 60_000)
    :ok
  end

  @opts [client: :patterns_it_client]

  test "get_scopes/1 against a fresh event store is an empty success, not a failure" do
    assert {:ok, []} = Patterns.get_scopes(@opts)
  end

  test "get_patterns_at/3 against a scope with no mined behavior is an empty success" do
    assert {:ok, []} = Patterns.get_patterns_at("no-such-scope", nil, @opts)
  end

  test "get_patterns_for_scope/2 against a scope with no mined behavior is an empty success" do
    assert {:ok, []} = Patterns.get_patterns_for_scope("no-such-scope", @opts)
  end
end
