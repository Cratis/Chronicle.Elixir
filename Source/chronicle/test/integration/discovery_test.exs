# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

# Round trip against a real kernel for artifact identity drift detection. Opt in like the
# other integration tests: point CHRONICLE_INTEGRATION_CONNECTION_STRING at a development
# kernel and run `mix test --include integration`.
defmodule Chronicle.Integration.DiscoveryTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  defmodule OrderPlacedV1 do
    use Chronicle.Events.EventType, id: "disco-order-placed", generation: 1
    defstruct [:total]
  end

  # Same id and generation as OrderPlacedV1, with a field added — the struct changed shape
  # without a bumped generation.
  defmodule OrderPlacedV1Changed do
    use Chronicle.Events.EventType, id: "disco-order-placed", generation: 1
    defstruct [:total, :currency]
  end

  defmodule TrackedEvent do
    use Chronicle.Events.EventType, id: "disco-tracked-event"
    defstruct [:value]
  end

  defmodule TrackedReactor do
    use Chronicle.Reactors.Reactor, id: "disco-tracked-reactor"

    @handles TrackedEvent

    @impl true
    def handle(%TrackedEvent{}, _context), do: :ok
  end

  defp unique_store(prefix) do
    "#{prefix}-#{System.system_time(:millisecond)}-#{System.unique_integer([:positive])}"
  end

  defp connection_string, do: System.fetch_env!("CHRONICLE_INTEGRATION_CONNECTION_STRING")

  describe "schema_changed_without_generation" do
    # The kernel itself refuses a generation's schema to change without a bump, independent of
    # our own `drift_policy` — so neither :warn nor :fail ever reaches :registered here. The
    # policies still differ in *why* registration is stuck: under :fail, our own drift check
    # refuses before ever calling the kernel; under :warn, it logs and proceeds, and it is the
    # kernel's own rejection that stops registration.
    test "a changed event struct with no generation bump is reported under :warn, and blocks locally under :fail" do
      event_store = unique_store("disco-schema")

      {:ok, _} =
        Chronicle.Client.start_link(
          name: :disco_schema_warn_client,
          connection_string: connection_string(),
          event_store: event_store,
          discover: false,
          event_types: [OrderPlacedV1]
        )

      :ok = Chronicle.Client.await_registration(:disco_schema_warn_client, 60_000)

      {:ok, _} =
        Chronicle.Client.start_link(
          name: :disco_schema_warn_client2,
          connection_string: connection_string(),
          event_store: event_store,
          discover: false,
          event_types: [OrderPlacedV1Changed],
          drift_policy: :warn,
          registration: [initial_delay: 200, max_delay: 200]
        )

      warn_status = wait_for_attempt(:disco_schema_warn_client2)
      assert match?({:exception, _}, warn_status.error)

      findings = Chronicle.Client.identity_drift(:disco_schema_warn_client2)
      assert Enum.any?(findings, &(&1.reason == :schema_changed_without_generation))

      {:ok, _} =
        Chronicle.Client.start_link(
          name: :disco_schema_fail_client,
          connection_string: connection_string(),
          event_store: event_store,
          discover: false,
          event_types: [OrderPlacedV1Changed],
          drift_policy: :fail,
          registration: [initial_delay: 200, max_delay: 200]
        )

      fail_status = wait_for_attempt(:disco_schema_fail_client)
      assert match?({:artifact_identity_drift, _}, fail_status.error)

      findings = Chronicle.Client.identity_drift(:disco_schema_fail_client)
      assert Enum.any?(findings, &(&1.reason == :schema_changed_without_generation))
    end
  end

  describe "observer_missing_from_code" do
    test "a registered reactor absent from the second client's code is reported" do
      event_store = unique_store("disco-observer")

      {:ok, _} =
        Chronicle.Client.start_link(
          name: :disco_observer_client1,
          connection_string: connection_string(),
          event_store: event_store,
          discover: false,
          event_types: [TrackedEvent],
          reactors: [TrackedReactor]
        )

      :ok = Chronicle.Client.await_registration(:disco_observer_client1, 60_000)
      wait_for_observer(:disco_observer_client1, "disco-tracked-reactor")

      {:ok, _} =
        Chronicle.Client.start_link(
          name: :disco_observer_client2,
          connection_string: connection_string(),
          event_store: event_store,
          discover: false,
          event_types: [TrackedEvent],
          drift_policy: :warn
        )

      :ok = Chronicle.Client.await_registration(:disco_observer_client2, 60_000)

      findings = Chronicle.Client.identity_drift(:disco_observer_client2)

      assert Enum.any?(
               findings,
               &(&1.reason == :observer_missing_from_code and &1.id == "disco-tracked-reactor")
             )
    end
  end

  defp wait_for_attempt(client, attempts \\ 40) do
    status = Chronicle.Client.registration_status(client)

    cond do
      status.attempts > 0 ->
        status

      attempts == 0 ->
        flunk("#{client} never attempted registration")

      true ->
        Process.sleep(250)
        wait_for_attempt(client, attempts - 1)
    end
  end

  defp wait_for_observer(client, observer_id, attempts \\ 40) do
    case Chronicle.Observers.get_all(client: client, namespace: "Default") do
      {:ok, observers} ->
        if Enum.any?(observers, &(&1.id == observer_id and &1.event_sequence_id == "event-log")) do
          :ok
        else
          retry_wait_for_observer(client, observer_id, attempts)
        end

      {:error, _} ->
        retry_wait_for_observer(client, observer_id, attempts)
    end
  end

  defp retry_wait_for_observer(client, observer_id, 0),
    do: flunk("observer #{observer_id} never appeared for #{client}")

  defp retry_wait_for_observer(client, observer_id, attempts) do
    Process.sleep(250)
    wait_for_observer(client, observer_id, attempts - 1)
  end
end
