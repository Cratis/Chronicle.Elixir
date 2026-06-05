# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule ConsoleSample.WebHooks.AccountEvents do
  @moduledoc false

  use Chronicle.WebHooks.Webhook,
    id: "console-sample-account-events",
    target_url: "https://example.com/chronicle/console-sample"

  alias Chronicle.WebHooks.DefinitionBuilder
  alias ConsoleSample.Events.{AccountOpened, FundsDeposited, FundsWithdrawn}

  @impl true
  def define(builder) do
    builder
    |> DefinitionBuilder.with_event_type(AccountOpened)
    |> DefinitionBuilder.with_event_type(FundsDeposited)
    |> DefinitionBuilder.with_event_type(FundsWithdrawn)
    |> DefinitionBuilder.with_header("x-sample", "console")
    |> DefinitionBuilder.not_replayable()
  end
end
