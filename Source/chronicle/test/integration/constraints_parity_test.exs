# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

# Round trip against a real kernel for constraints parity (issue #143). Opt in like the other
# integration tests: point CHRONICLE_INTEGRATION_CONNECTION_STRING at a development kernel and run
# `mix test --include integration`.
defmodule Chronicle.Integration.ConstraintsParityTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  alias Chronicle.EventSequences.{AppendResult, EventLog}

  defmodule CodeClaimed do
    use Chronicle.Events.EventType, id: "cp-code-claimed"
    defstruct code: ""

    unique(:code, name: "cp-per-event-source-code", mode: :per_event_source)
  end

  defmodule VersionRegistered do
    use Chronicle.Events.EventType, id: "cp-version-registered"
    defstruct version_id: ""

    unique(:version_id, name: "cp-per-value-version", mode: :per_value)
  end

  defmodule VersionRemoved do
    use Chronicle.Events.EventType, id: "cp-version-removed"
    defstruct version_id: ""

    remove_constraint("cp-per-value-version", properties: [:version_id])
  end

  defmodule ProjectInitialized do
    use Chronicle.Events.EventType, id: "cp-project-initialized"
    defstruct []

    unique_event_type(name: "cp-one-initialization")
  end

  defmodule StandaloneUserRegistered do
    use Chronicle.Events.EventType, id: "cp-standalone-user-registered"
    defstruct email: ""
  end

  defmodule StandaloneUniqueEmail do
    use Chronicle.Events.Constraint

    unique name: "cp-standalone-unique-email" do
      on(StandaloneUserRegistered, [:email])
    end
  end

  setup_all do
    prefix = System.get_env("CHRONICLE_INTEGRATION_EVENT_STORE_PREFIX", "constraints-elixir")

    event_store =
      "#{prefix}-#{System.system_time(:millisecond)}-#{System.unique_integer([:positive])}"

    {:ok, _} =
      Chronicle.Client.start_link(
        name: :constraints_it_client,
        connection_string: System.fetch_env!("CHRONICLE_INTEGRATION_CONNECTION_STRING"),
        event_store: event_store,
        discover: false,
        event_types: [
          CodeClaimed,
          VersionRegistered,
          VersionRemoved,
          ProjectInitialized,
          StandaloneUserRegistered
        ],
        constraints: [StandaloneUniqueEmail]
      )

    :ok = Chronicle.Client.await_registration(:constraints_it_client, 60_000)
    :ok
  end

  @opts [client: :constraints_it_client]

  test ":per_event_source mode releases the previous value when it is replaced" do
    assert {:ok, _} = EventLog.append_with_result("pes-1", %CodeClaimed{code: "alpha"}, @opts)

    assert {:error, %AppendResult{constraint_violations: [_ | _]}} =
             EventLog.append_with_result("pes-2", %CodeClaimed{code: "alpha"}, @opts)

    # Replacing the value on the same event source releases "alpha" for a different source.
    assert {:ok, _} = EventLog.append_with_result("pes-1", %CodeClaimed{code: "beta"}, @opts)
    assert {:ok, _} = EventLog.append_with_result("pes-2", %CodeClaimed{code: "alpha"}, @opts)
  end

  test ":per_value mode holds the value until a removal event with properties releases it" do
    assert {:ok, _} =
             EventLog.append_with_result("pv-1", %VersionRegistered{version_id: "v1"}, @opts)

    assert {:error, %AppendResult{constraint_violations: [_ | _]}} =
             EventLog.append_with_result("pv-2", %VersionRegistered{version_id: "v1"}, @opts)

    assert {:ok, _} =
             EventLog.append_with_result("pv-1", %VersionRemoved{version_id: "v1"}, @opts)

    assert {:ok, _} =
             EventLog.append_with_result("pv-2", %VersionRegistered{version_id: "v1"}, @opts)
  end

  test "unique_event_type rejects a second append of the same event type for the event source" do
    assert {:ok, _} = EventLog.append_with_result("uet-1", %ProjectInitialized{}, @opts)

    assert {:error, %AppendResult{constraint_violations: [violation | _]}} =
             EventLog.append_with_result("uet-1", %ProjectInitialized{}, @opts)

    assert violation.constraint_name == "cp-one-initialization"
  end

  test "a standalone constraint module registered through :constraints is enforced" do
    assert {:ok, _} =
             EventLog.append_with_result(
               "standalone-1",
               %StandaloneUserRegistered{email: "standalone@example.com"},
               @opts
             )

    assert {:error, %AppendResult{constraint_violations: [violation | _]}} =
             EventLog.append_with_result(
               "standalone-2",
               %StandaloneUserRegistered{email: "standalone@example.com"},
               @opts
             )

    assert violation.constraint_name == "cp-standalone-unique-email"
  end

  # Registering every event type and constraint module `discover_loaded/0` finds across the
  # whole test suite against a live kernel is impractical here (it would register hundreds of
  # unrelated artifacts). That `StandaloneUniqueEmail` is discoverable at all is covered at the
  # unit level in `Chronicle.Events.ConstraintTest` ("Chronicle.Artifacts discovery"); this test
  # only needs to prove a module reached the kernel through the explicit `:constraints` option.
end
