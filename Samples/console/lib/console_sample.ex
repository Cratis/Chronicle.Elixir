# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule ConsoleSample do
  @moduledoc """
  Console demo for the Chronicle Elixir client.

  Demonstrates appending events and reading back a read model.
  """

  require Logger

  alias ConsoleSample.Events.{AccountOpened, FundsDeposited, FundsWithdrawn}
  alias ConsoleSample.ReadModels.Account

  @doc """
  Runs the demo scenario:
  1. Open a new account
  2. Deposit funds
  3. Withdraw funds
  4. Read back the account read model
  """
  def run_demo do
    # Give Chronicle time to connect, authenticate, establish the session, and register projections
    Process.sleep(8_000)

    account_id = "account-#{:rand.uniform(1_000_000)}"

    Logger.info("=== Chronicle Elixir Console Sample ===")
    Logger.info("Using account ID: #{account_id}")

    Logger.info("Appending AccountOpened event...")

    case Chronicle.append(account_id, %AccountOpened{
           account_id: account_id,
           owner_name: "Alice",
           initial_balance: 1000
         }) do
      :ok ->
        Logger.info("AccountOpened appended successfully")

      {:error, reason} ->
        Logger.error("Failed to append AccountOpened: #{inspect(reason)}")
    end

    Logger.info("Appending FundsDeposited event...")

    case Chronicle.append(account_id, %FundsDeposited{
           account_id: account_id,
           amount: 500
         }) do
      :ok -> Logger.info("FundsDeposited appended successfully")
      {:error, reason} -> Logger.error("Failed: #{inspect(reason)}")
    end

    Logger.info("Appending FundsWithdrawn event...")

    case Chronicle.append(account_id, %FundsWithdrawn{
           account_id: account_id,
           amount: 200
         }) do
      :ok -> Logger.info("FundsWithdrawn appended successfully")
      {:error, reason} -> Logger.error("Failed: #{inspect(reason)}")
    end

    # Allow the server-side projection and reactor/reducer to process events
    Process.sleep(6_000)

    Logger.info("Reading Account read model (projection)...")

    case Chronicle.read_model(Account, account_id) do
      {:ok, nil} ->
        Logger.warning("Projection read model not yet available.")

      {:ok, account} ->
        Logger.info("=== Account (projection) ===")
        Logger.info("  ID:           #{account.account_id}")
        Logger.info("  Owner:        #{account.owner_name}")
        Logger.info("  Balance:      #{account.balance}")
        Logger.info("  Transactions: #{account.transaction_count}")

      {:error, reason} ->
        Logger.error("Failed to read projection model: #{inspect(reason)}")
    end

    Logger.info("=== Demo complete ===")
  end
end
