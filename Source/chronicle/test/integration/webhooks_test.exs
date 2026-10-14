# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

# Round trip against a real kernel for webhook registration. Opt in like the other
# integration tests: point CHRONICLE_INTEGRATION_CONNECTION_STRING at a development kernel and run
# `mix test --include integration`.
defmodule Chronicle.Integration.WebhooksTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  alias Chronicle.WebHooks.DefinitionBuilder

  defmodule NoteAdded do
    use Chronicle.Events.EventType, id: "wh-note-added"
    defstruct text: ""
  end

  setup_all do
    prefix = System.get_env("CHRONICLE_INTEGRATION_EVENT_STORE_PREFIX", "webhooks-elixir")

    {:ok, _} =
      Chronicle.Client.start_link(
        name: :webhooks_it_client,
        connection_string: System.fetch_env!("CHRONICLE_INTEGRATION_CONNECTION_STRING"),
        event_store:
          "#{prefix}-#{System.system_time(:millisecond)}-#{System.unique_integer([:positive])}",
        discover: false,
        event_types: [NoteAdded]
      )

    :ok = Chronicle.Client.await_registration(:webhooks_it_client, 60_000)
    :ok
  end

  @opts [client: :webhooks_it_client]

  test "a webhook registered as not replayable reads back as not replayable" do
    assert :ok =
             Chronicle.register_webhook(
               "not-replayable-webhook",
               "https://example.com/chronicle/webhooks",
               fn builder ->
                 builder
                 |> DefinitionBuilder.with_event_type(NoteAdded)
                 |> DefinitionBuilder.not_replayable()
               end,
               @opts
             )

    webhook =
      wait_for(fn ->
        {:ok, webhooks} = Chronicle.get_webhooks(@opts)
        Enum.find(webhooks, &(&1.id == "not-replayable-webhook"))
      end)

    assert %{replayable?: false} = webhook
  end

  defp wait_for(fetch, attempts \\ 40) do
    case fetch.() do
      nil when attempts > 0 ->
        Process.sleep(250)
        wait_for(fetch, attempts - 1)

      result ->
        result
    end
  end
end
