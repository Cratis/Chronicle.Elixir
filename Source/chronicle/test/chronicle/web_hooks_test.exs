# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.WebHooksTest do
  use ExUnit.Case, async: true

  alias Chronicle.WebHooks.{DefinitionBuilder, Webhook}

  defmodule AccountOpened do
    use Chronicle.Events.EventType, id: "account-opened-v1"
    defstruct [:account_id]
  end

  defmodule FundsDeposited do
    use Chronicle.Events.EventType, id: "funds-deposited-v1"
    defstruct [:account_id, :amount]
  end

  defmodule AccountEventsWebhook do
    use Webhook,
      id: "account-events",
      target_url: "https://example.com/chronicle/webhooks",
      event_sequence_id: "event-log"

    @impl true
    def define(builder) do
      builder
      |> DefinitionBuilder.with_event_type(AccountOpened)
      |> DefinitionBuilder.with_event_type(FundsDeposited)
      |> DefinitionBuilder.with_header("x-source", "chronicle-elixir")
      |> DefinitionBuilder.not_replayable()
    end
  end

  describe "use Chronicle.WebHooks.Webhook" do
    test "exposes discoverable metadata" do
      assert AccountEventsWebhook.__chronicle_webhook__(:id) == "account-events"

      assert AccountEventsWebhook.__chronicle_webhook__(:target_url) ==
               "https://example.com/chronicle/webhooks"

      assert AccountEventsWebhook.__chronicle_webhook__(:event_sequence_id) == "event-log"
    end
  end

  describe "DefinitionBuilder.build/3" do
    test "uses explicitly configured event types" do
      definition =
        [AccountOpened, FundsDeposited]
        |> DefinitionBuilder.new()
        |> AccountEventsWebhook.define()
        |> DefinitionBuilder.build("account-events", "https://example.com/chronicle/webhooks")

      assert definition.id == "account-events"
      assert definition.event_sequence_id == "event-log"
      assert definition.replayable? == false
      assert definition.active? == true
      assert definition.target.url == "https://example.com/chronicle/webhooks"
      assert definition.target.headers == %{"x-source" => "chronicle-elixir"}

      assert Enum.map(definition.event_types, & &1.id) == [
               "account-opened-v1",
               "funds-deposited-v1"
             ]
    end

    test "falls back to all registered event types when none are selected" do
      definition =
        [AccountOpened, FundsDeposited]
        |> DefinitionBuilder.new()
        |> DefinitionBuilder.build("all-events", "https://example.com/all")

      assert Enum.map(definition.event_types, & &1.id) == [
               "account-opened-v1",
               "funds-deposited-v1"
             ]
    end
  end

  describe "Chronicle.Artifacts.discover_loaded/0" do
    test "includes discoverable webhooks" do
      assert AccountEventsWebhook in Chronicle.Artifacts.discover_loaded().webhooks
    end
  end
end
