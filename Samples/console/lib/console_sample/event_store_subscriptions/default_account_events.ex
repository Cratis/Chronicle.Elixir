# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule ConsoleSample.EventStoreSubscriptions.DefaultAccountEvents do
  @moduledoc """
  Auto-discovered event store subscription that imports account events from the
  `default` event store into the console sample's event store.
  """

  use Chronicle.EventStoreSubscriptions.Subscription,
    id: "console-sample-default-account-events",
    source_event_store: "default"

  alias Chronicle.EventStoreSubscriptions.DefinitionBuilder

  @impl true
  def define(builder) do
    builder
    |> DefinitionBuilder.with_event_type(ConsoleSample.Events.AccountOpened)
    |> DefinitionBuilder.with_event_type(ConsoleSample.Events.FundsDeposited)
    |> DefinitionBuilder.with_event_type(ConsoleSample.Events.FundsWithdrawn)
  end
end
