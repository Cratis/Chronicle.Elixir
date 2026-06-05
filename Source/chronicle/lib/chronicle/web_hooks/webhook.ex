# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.WebHooks.Webhook do
  @moduledoc """
  Behaviour and macro for defining discoverable Chronicle webhooks.

  Discoverable webhooks follow the same pattern as read models and constraints:
  metadata is captured at compile time and exposed through
  `__chronicle_webhook__/1`.

  ## Usage

      defmodule MyApp.WebHooks.AccountEvents do
        use Chronicle.WebHooks.Webhook,
          target_url: "https://example.com/chronicle/webhooks"

        alias Chronicle.WebHooks.DefinitionBuilder

        @impl true
        def define(builder) do
          builder
          |> DefinitionBuilder.with_event_type(MyApp.Events.AccountOpened)
          |> DefinitionBuilder.with_header("x-source", "my-app")
        end
      end

  Options for `use Chronicle.WebHooks.Webhook`:

    * `:target_url` — **required** webhook target URL
    * `:id` — stable webhook identifier. Defaults to the module's last segment.
    * `:event_sequence_id` — optional explicit event sequence identifier
  """

  alias Chronicle.WebHooks.DefinitionBuilder

  @callback define(DefinitionBuilder.t()) :: DefinitionBuilder.t()
  @callback __chronicle_webhook__(:id | :target_url | :event_sequence_id) :: term()

  defmacro __using__(opts) do
    webhook_id = Keyword.get(opts, :id, __CALLER__.module |> Module.split() |> List.last())
    target_url = Keyword.fetch!(opts, :target_url)
    event_sequence_id = Keyword.get(opts, :event_sequence_id)

    quote bind_quoted: [
            webhook_id: webhook_id,
            target_url: target_url,
            event_sequence_id: event_sequence_id
          ] do
      @behaviour Chronicle.WebHooks.Webhook

      @chronicle_webhook_id webhook_id
      @chronicle_webhook_target_url target_url
      @chronicle_webhook_event_sequence_id event_sequence_id

      @impl Chronicle.WebHooks.Webhook
      def define(builder), do: builder

      defoverridable define: 1

      @doc false
      def __chronicle_webhook__(:id), do: @chronicle_webhook_id
      def __chronicle_webhook__(:target_url), do: @chronicle_webhook_target_url
      def __chronicle_webhook__(:event_sequence_id), do: @chronicle_webhook_event_sequence_id
    end
  end
end
