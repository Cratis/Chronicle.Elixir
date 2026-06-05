# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.EventStoreSubscriptions.Subscription do
  @moduledoc """
  Behaviour and macro for defining discoverable Chronicle event store subscriptions.

  Discoverable subscriptions follow the same pattern as reactors and webhooks:
  metadata is captured at compile time and exposed through
  `__chronicle_event_store_subscription__/1`.

  ## Usage

      defmodule MyApp.EventStoreSubscriptions.DefaultAccountEvents do
        use Chronicle.EventStoreSubscriptions.Subscription,
          source_event_store: "default"

        alias Chronicle.EventStoreSubscriptions.DefinitionBuilder

        @impl true
        def define(builder) do
          builder
          |> DefinitionBuilder.with_event_type(MyApp.Events.AccountOpened)
          |> DefinitionBuilder.with_event_type(MyApp.Events.FundsDeposited)
        end
      end

  Options for `use Chronicle.EventStoreSubscriptions.Subscription`:

    * `:source_event_store` — **required** source event store name
    * `:id` — stable subscription identifier. Defaults to the module name.
  """

  alias Chronicle.EventStoreSubscriptions.DefinitionBuilder

  @callback define(DefinitionBuilder.t()) :: DefinitionBuilder.t()
  @callback __chronicle_event_store_subscription__(:id | :source_event_store) :: term()

  defmacro __using__(opts) do
    subscription_id = Keyword.get(opts, :id, __CALLER__.module |> to_string())
    source_event_store = Keyword.fetch!(opts, :source_event_store)

    quote bind_quoted: [
            subscription_id: subscription_id,
            source_event_store: source_event_store
          ] do
      @behaviour Chronicle.EventStoreSubscriptions.Subscription

      @chronicle_event_store_subscription_id subscription_id
      @chronicle_event_store_subscription_source_event_store source_event_store

      @impl Chronicle.EventStoreSubscriptions.Subscription
      def define(builder), do: builder

      defoverridable define: 1

      @doc false
      def __chronicle_event_store_subscription__(:id),
        do: @chronicle_event_store_subscription_id

      def __chronicle_event_store_subscription__(:source_event_store),
        do: @chronicle_event_store_subscription_source_event_store
    end
  end
end
