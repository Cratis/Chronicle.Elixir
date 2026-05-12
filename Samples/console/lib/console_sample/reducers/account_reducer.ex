# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule ConsoleSample.Reducers.AccountReducer do
  @moduledoc """
  Reduces account events into the `AccountSummary` read model.

  Demonstrates the `Chronicle.Reducer` behaviour — implement `reduce/3` for
  each event type and declare them with `@handles`. Chronicle calls the reducer
  with each new event since the last stored state, and stores the returned
  state back to MongoDB via the configured sink.

  Note: reducers and projections cannot share a read model. `AccountSummary`
  is the reducer-owned counterpart to the projection-owned `Account` model.
  """

  use Chronicle.Reducer, model: ConsoleSample.ReadModels.AccountSummary

  require Logger

  alias ConsoleSample.Events.{AccountOpened, FundsDeposited, FundsWithdrawn}
  alias ConsoleSample.ReadModels.AccountSummary

  @handles AccountOpened
  @handles FundsDeposited
  @handles FundsWithdrawn

  @impl true
  def reduce(%AccountOpened{} = event, _model, _context) do
    summary = %AccountSummary{
      account_id: event.account_id,
      owner_name: event.owner_name,
      balance: event.initial_balance,
      transaction_count: 0
    }

    Logger.info(
      "[Reducer] AccountOpened → balance=#{summary.balance}, owner=#{summary.owner_name}"
    )

    summary
  end

  def reduce(%FundsDeposited{} = event, model, _context) do
    summary = %{
      model
      | balance: model.balance + event.amount,
        transaction_count: model.transaction_count + 1
    }

    Logger.info("[Reducer] FundsDeposited +#{event.amount} → balance=#{summary.balance}")
    summary
  end

  def reduce(%FundsWithdrawn{} = event, model, _context) do
    summary = %{
      model
      | balance: model.balance - event.amount,
        transaction_count: model.transaction_count + 1
    }

    Logger.info("[Reducer] FundsWithdrawn -#{event.amount} → balance=#{summary.balance}")
    summary
  end
end
