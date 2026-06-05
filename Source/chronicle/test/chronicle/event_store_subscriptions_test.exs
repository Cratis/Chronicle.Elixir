# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.EventStoreSubscriptionsTest do
  use ExUnit.Case, async: true

  alias Chronicle.EventStoreSubscriptions.DefinitionBuilder

  defmodule AccountOpened do
    use Chronicle.EventType, id: "account-opened", generation: 2
    defstruct [:account_id]
  end

  defmodule FundsDeposited do
    use Chronicle.EventType, id: "funds-deposited"
    defstruct [:account_id, :amount]
  end

  defmodule DefaultAccountEvents do
    use Chronicle.EventStoreSubscriptions.Subscription,
      source_event_store: "default"

    alias Chronicle.EventStoreSubscriptions.DefinitionBuilder

    @impl true
    def define(builder) do
      builder
      |> DefinitionBuilder.with_event_type(AccountOpened)
      |> DefinitionBuilder.with_event_type(FundsDeposited)
    end
  end

  defmodule CustomSubscription do
    use Chronicle.EventStoreSubscriptions.Subscription,
      id: "custom-subscription",
      source_event_store: "legacy"
  end

  describe "DefinitionBuilder" do
    test "uses explicitly configured event types" do
      definition =
        DefinitionBuilder.new([AccountOpened])
        |> DefinitionBuilder.with_event_type(FundsDeposited)
        |> DefinitionBuilder.build("deposit-events", "default")

      assert definition.id == "deposit-events"
      assert definition.source_event_store == "default"

      assert Enum.map(definition.event_types, & &1.id) == ["funds-deposited"]
    end

    test "falls back to registered event types when none are selected" do
      definition =
        DefinitionBuilder.new([AccountOpened, FundsDeposited])
        |> DefinitionBuilder.build("all-events", "default")

      assert Enum.map(definition.event_types, & &1.id) == ["account-opened", "funds-deposited"]
    end
  end

  describe "use Chronicle.EventStoreSubscriptions.Subscription" do
    test "defaults id to module name" do
      assert DefaultAccountEvents.__chronicle_event_store_subscription__(:id) ==
               to_string(DefaultAccountEvents)
    end

    test "exposes the source event store" do
      assert DefaultAccountEvents.__chronicle_event_store_subscription__(:source_event_store) ==
               "default"
    end

    test "supports explicit id" do
      assert CustomSubscription.__chronicle_event_store_subscription__(:id) ==
               "custom-subscription"
    end

    test "artifacts discovery includes event store subscriptions" do
      discovered = Chronicle.Artifacts.discover_loaded()
      assert DefaultAccountEvents in discovered.event_store_subscriptions
      assert CustomSubscription in discovered.event_store_subscriptions
    end
  end
end
