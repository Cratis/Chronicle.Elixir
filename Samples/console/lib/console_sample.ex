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
  alias Chronicle.{CausationManager, CorrelationIdManager, Identity}

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
    correlation_id = Chronicle.CorrelationId.create()

    Chronicle.set_correlation_id(correlation_id)

    Chronicle.set_identity(
      Identity.new("console-sample-user", "Console Sample", "console-sample")
    )

    CausationManager.define_root(%{application: "console-sample"})
    CausationManager.add("ConsoleSample.RunDemo", %{account_id: account_id})

    Logger.info("=== Chronicle Elixir Console Sample ===")
    Logger.info("Using account ID: #{account_id}")
    Logger.info("Correlation ID: #{correlation_id.value}")

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

    case Chronicle.has_events_for?(account_id) do
      {:ok, true} -> Logger.info("Event sequence has events for #{account_id}")
      {:ok, false} -> Logger.warning("No events found for #{account_id}")
      {:error, reason} -> Logger.error("Failed checking sequence state: #{inspect(reason)}")
    end

    case Chronicle.get_tail_sequence_number(account_id) do
      {:ok, sequence_number} -> Logger.info("Tail sequence number for #{account_id}: #{sequence_number}")
      {:error, reason} -> Logger.error("Failed getting tail sequence number: #{inspect(reason)}")
    end

    case Chronicle.get_event_stores() do
      {:ok, stores} -> Logger.info("Event stores: #{inspect(stores)}")
      {:error, reason} -> Logger.error("Failed getting event stores: #{inspect(reason)}")
    end

    case Chronicle.get_namespaces() do
      {:ok, namespaces} -> Logger.info("Namespaces: #{inspect(namespaces)}")
      {:error, reason} -> Logger.error("Failed getting namespaces: #{inspect(reason)}")
    end

    Logger.info("=== Demo complete ===")

    Chronicle.clear_identity()
    CorrelationIdManager.clear()
    CausationManager.clear()
  end
end
