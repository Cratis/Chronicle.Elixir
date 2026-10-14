# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

# Round trip against a real kernel for tombstone, compensation and generation_for registration.
# Opt in like the other integration tests: point CHRONICLE_INTEGRATION_CONNECTION_STRING at a
# development kernel and run `mix test --include integration`.
defmodule Chronicle.Integration.EventTypeRegistrationTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  alias Chronicle.Connections.Connection

  alias Cratis.Chronicle.Contracts.EventTypes.{
    AllEventTypeGenerationsRequest,
    AllEventTypesRequest,
    EventTypes
  }

  defmodule AccountClosed do
    use Chronicle.Events.EventType, id: "etr-account-closed", tombstone: true
    defstruct []
  end

  defmodule PaymentFailed do
    use Chronicle.Events.EventType, id: "etr-payment-failed"
    defstruct []
  end

  defmodule PaymentReversed do
    use Chronicle.Events.EventType,
      id: "etr-payment-reversed",
      compensation_for: PaymentFailed

    defstruct []
  end

  defmodule OrderPlacedV2 do
    use Chronicle.Events.EventType, id: "etr-order-placed", generation: 2
    defstruct []
  end

  defmodule OrderPlacedV1 do
    use Chronicle.Events.EventType, generation_for: OrderPlacedV2, generation: 1
    defstruct []
  end

  defmodule OrderPlacedV2Migration do
    use Chronicle.Events.Migration,
      from: {OrderPlacedV1, generation: 1},
      to: {OrderPlacedV2, generation: 2}

    def upcast(builder), do: builder
    def downcast(builder), do: builder
  end

  setup_all do
    prefix = System.get_env("CHRONICLE_INTEGRATION_EVENT_STORE_PREFIX", "etr-elixir")

    {:ok, _} =
      Chronicle.Client.start_link(
        name: :etr_it_client,
        connection_string: System.fetch_env!("CHRONICLE_INTEGRATION_CONNECTION_STRING"),
        event_store:
          "#{prefix}-#{System.system_time(:millisecond)}-#{System.unique_integer([:positive])}",
        discover: false,
        event_types: [
          AccountClosed,
          PaymentFailed,
          PaymentReversed,
          OrderPlacedV1,
          OrderPlacedV2
        ],
        migrations: [OrderPlacedV2Migration]
      )

    :ok = Chronicle.Client.await_registration(:etr_it_client, 60_000)

    config = Chronicle.Client.config(:etr_it_client)
    {:ok, channel} = Connection.channel(Chronicle.Client.connection_name(:etr_it_client))

    %{channel: channel, event_store: config.event_store}
  end

  test "a tombstone event type is listed as a tombstone", %{channel: channel, event_store: store} do
    entry = wait_for_event_type(channel, store, "etr-account-closed")
    assert entry."Type"."Tombstone" == true
  end

  test "compensation_for is listed through the schema's compensationFor extension", %{
    channel: channel,
    event_store: store
  } do
    entry = wait_for_event_type(channel, store, "etr-payment-reversed")
    schema = Jason.decode!(entry."Schema")
    assert schema["compensationFor"] == "etr-payment-failed"
  end

  test "generation_for registers both generations under the same event type id", %{
    channel: channel,
    event_store: store
  } do
    request =
      struct(AllEventTypeGenerationsRequest, EventStore: store, EventTypeId: "etr-order-placed")

    {:ok, response} = EventTypes.Stub.all_event_type_generations(channel, request)

    generations =
      response."Data" |> Enum.map(& &1."Type"."Generation") |> Enum.sort()

    assert generations == [1, 2]
  end

  defp wait_for_event_type(channel, store, event_type_id, attempts \\ 40) do
    request = struct(AllEventTypesRequest, EventStore: store)
    {:ok, response} = EventTypes.Stub.all_event_types(channel, request)

    case Enum.find(response."Data", &(&1."Id" == event_type_id)) do
      nil when attempts > 0 ->
        Process.sleep(250)
        wait_for_event_type(channel, store, event_type_id, attempts - 1)

      nil ->
        flunk("event type #{event_type_id} never appeared in AllEventTypes")

      entry ->
        entry
    end
  end
end
