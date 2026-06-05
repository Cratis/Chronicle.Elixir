# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule ConsoleSample.Reactors.NotificationReactor do
  @moduledoc """
  Reacts to account events by printing console notifications.

  Demonstrates the `Chronicle.Reactor` behaviour — implement `handle/2` for
  each event type you want to observe, and declare them with `@handles`.
  """

  use Chronicle.Reactor

  require Logger

  @handles ConsoleSample.Events.AccountOpened
  @handles ConsoleSample.Events.FundsDeposited
  @handles ConsoleSample.Events.FundsWithdrawn

  @impl true
  def handle(%ConsoleSample.Events.AccountOpened{} = event, context) do
    Logger.info(
      "[Reactor] Account opened: #{event.account_id} for #{event.full_name} " <>
        "with initial balance #{event.initial_balance} and tier #{event.account_tier} " <>
        "(seq=#{context.sequence_number})"
    )

    :ok
  end

  def handle(%ConsoleSample.Events.FundsDeposited{} = event, context) do
    Logger.info(
      "[Reactor] Funds deposited: #{event.amount} to #{event.account_id} " <>
        "(seq=#{context.sequence_number})"
    )

    :ok
  end

  def handle(%ConsoleSample.Events.FundsWithdrawn{} = event, context) do
    Logger.info(
      "[Reactor] Funds withdrawn: #{event.amount} from #{event.account_id} " <>
        "(seq=#{context.sequence_number})"
    )

    :ok
  end
end
