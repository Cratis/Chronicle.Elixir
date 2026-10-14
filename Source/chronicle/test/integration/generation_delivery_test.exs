# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

# Round trip against a real kernel for pinned generation delivery. Opt in like the other
# integration tests: point CHRONICLE_INTEGRATION_CONNECTION_STRING at a development kernel and run
# `mix test --include integration`.
#
# Needs a kernel that resolves generation delivery per observer registration (Cratis/Chronicle#4747).
defmodule Chronicle.Integration.GenerationDeliveryTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  defmodule AccountOpenedV1 do
    use Chronicle.Events.EventType, id: "gd-account-opened", generation: 1
    defstruct owner_name: ""
  end

  defmodule AccountOpened do
    use Chronicle.Events.EventType, id: "gd-account-opened", generation: 2
    defstruct full_name: "", account_tier: ""
  end

  defmodule AccountOpenedV2Migration do
    use Chronicle.Events.Migration,
      from: {AccountOpenedV1, generation: 1},
      to: {AccountOpened, generation: 2}

    alias Chronicle.Events.MigrationBuilder

    @impl true
    def upcast(builder) do
      builder
      |> MigrationBuilder.default_value(:account_tier, "standard")
      |> MigrationBuilder.rename_property(:owner_name, :full_name)
    end

    @impl true
    def downcast(builder) do
      MigrationBuilder.rename_property(builder, :full_name, :owner_name)
    end
  end

  defmodule PinnedSpy do
    use Chronicle.Reactors.Reactor, generation_delivery: :pinned

    @handles AccountOpenedV1

    def handle(event, context) do
      send(:generation_delivery_it, {:handled, event, context})
      :ok
    end
  end

  setup_all do
    prefix = System.get_env("CHRONICLE_INTEGRATION_EVENT_STORE_PREFIX", "gendelivery-elixir")

    {:ok, _} =
      Chronicle.Client.start_link(
        name: :generation_delivery_it_client,
        connection_string: System.fetch_env!("CHRONICLE_INTEGRATION_CONNECTION_STRING"),
        event_store:
          "#{prefix}-#{System.system_time(:millisecond)}-#{System.unique_integer([:positive])}",
        discover: false,
        event_types: [AccountOpenedV1, AccountOpened],
        migrations: [AccountOpenedV2Migration],
        reactors: [PinnedSpy]
      )

    :ok = Chronicle.Client.await_registration(:generation_delivery_it_client, 60_000)
    :ok
  end

  setup do
    Process.register(self(), :generation_delivery_it)
    on_exit(fn -> if Process.whereis(:generation_delivery_it), do: Process.unregister(:generation_delivery_it) end)
  end

  @opts [client: :generation_delivery_it_client]

  test "a pinned reactor registered against the older generation receives the original content, with appended_generation reporting the generation actually appended" do
    event = %AccountOpened{full_name: "Ada Lovelace", account_tier: "standard"}

    assert :ok = Chronicle.EventSequences.EventLog.append("gd-1", event, @opts)

    assert_receive {:handled, %AccountOpenedV1{owner_name: "Ada Lovelace"}, context}, 15_000
    assert context.appended_generation == 2
  end
end
