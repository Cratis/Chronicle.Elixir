# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule ConsoleSample do
  @moduledoc """
  Console demo for the Chronicle Elixir client.

  Demonstrates migrations, transaction-aware appends, read models, jobs,
  webhooks, and event store subscriptions.
  """

  require Logger

  alias ConsoleSample.Events.{FundsDeposited, FundsWithdrawn, LegacyAccountOpened}
  alias ConsoleSample.ReadModels.{Account, AccountSummary}
  alias Chronicle.EventStoreSubscriptions.DefinitionBuilder
  alias Chronicle.{CausationManager, CorrelationIdManager, Identity}
  alias Chronicle.Events.ConcurrencyScope
  alias Chronicle.Transactions.UnitOfWork

  @doc """
  Runs the demo scenario:
  1. Append the legacy `LegacyAccountOpened` generation 1 event
  2. Let Chronicle upcast it to `AccountOpened` generation 2 through the registered migration
  3. Read the current tail sequence number
  4. Buffer deposit and withdrawal events in a unit of work with a concurrency scope
  5. Commit the unit of work
  6. Read back the account read model
  7. Register an imperative event store subscription and remove it again
  8. Inspect registered webhooks and current jobs
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

    Logger.info("Appending LegacyAccountOpened generation 1 event...")

    Logger.info(
      "Chronicle should upcast it to AccountOpened generation 2 with account_tier=\"standard\"."
    )

    case Chronicle.append(account_id, %LegacyAccountOpened{
           account_id: account_id,
           owner_name: "Alice",
           initial_balance: 1000
         }) do
      :ok ->
        Logger.info("LegacyAccountOpened appended successfully")
        append_with_concurrency_scope(account_id)

      {:error, reason} ->
        Logger.error("Failed to append LegacyAccountOpened: #{inspect(reason)}")
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
        Logger.info("  Owner:        #{account.full_name}")
        Logger.info("  Tier:         #{account.account_tier}")
        Logger.info("  Balance:      #{account.balance}")
        Logger.info("  Transactions: #{account.transaction_count}")

      {:error, reason} ->
        Logger.error("Failed to read projection model: #{inspect(reason)}")
    end

    showcase_read_models(account_id)

    case Chronicle.has_events_for?(account_id) do
      {:ok, true} -> Logger.info("Event sequence has events for #{account_id}")
      {:ok, false} -> Logger.warning("No events found for #{account_id}")
      {:error, reason} -> Logger.error("Failed checking sequence state: #{inspect(reason)}")
    end

    case Chronicle.get_tail_sequence_number(account_id) do
      {:ok, sequence_number} ->
        Logger.info("Tail sequence number for #{account_id}: #{sequence_number}")

      {:error, reason} ->
        Logger.error("Failed getting tail sequence number: #{inspect(reason)}")
    end

    case Chronicle.get_event_stores() do
      {:ok, stores} -> Logger.info("Event stores: #{inspect(stores)}")
      {:error, reason} -> Logger.error("Failed getting event stores: #{inspect(reason)}")
    end

    case Chronicle.get_namespaces() do
      {:ok, namespaces} -> Logger.info("Namespaces: #{inspect(namespaces)}")
      {:error, reason} -> Logger.error("Failed getting namespaces: #{inspect(reason)}")
    end

    Logger.info(
      "Auto-discovered event store subscriptions are registered during Chronicle.Client startup."
    )

    demo_event_store_subscription()

    Logger.info("Listing registered webhooks...")

    case Chronicle.get_webhooks() do
      {:ok, webhooks} when webhooks == [] ->
        Logger.warning("No webhooks are currently registered.")

      {:ok, webhooks} ->
        Enum.each(webhooks, fn webhook ->
          Logger.info(
            "Webhook #{webhook.id} -> #{webhook.target.url} (#{length(webhook.event_types)} event type(s))"
          )
        end)

      {:error, reason} ->
        Logger.error("Failed getting webhooks: #{inspect(reason)}")
    end

    Logger.info("Listing Chronicle jobs...")

    case Chronicle.get_jobs() do
      {:ok, []} ->
        Logger.info("No jobs are currently active in Chronicle.")

      {:ok, [job | _] = jobs} ->
        Logger.info("Jobs: #{length(jobs)}")
        Logger.info("First job #{job.id} is #{job.status}")

        case Chronicle.get_job_steps(job.id) do
          {:ok, steps} -> Logger.info("First job has #{length(steps)} step(s)")
          {:error, reason} -> Logger.error("Failed getting job steps: #{inspect(reason)}")
        end

      {:error, reason} ->
        Logger.error("Failed getting jobs: #{inspect(reason)}")
    end

    Logger.info("=== Demo complete ===")

    Chronicle.clear_identity()
    CorrelationIdManager.clear()
    CausationManager.clear()
  end

  defp demo_event_store_subscription do
    subscription_id = "console-sample-default-deposits"

    Logger.info("Registering an imperative event store subscription from the default store...")

    case Chronicle.subscribe_to_event_store(subscription_id, "default", fn builder ->
           builder
           |> DefinitionBuilder.with_event_type(FundsDeposited)
         end) do
      :ok ->
        Logger.info("Registered event store subscription #{subscription_id}")

        case Chronicle.unsubscribe_from_event_store(subscription_id) do
          :ok ->
            Logger.info("Removed event store subscription #{subscription_id}")

          {:error, reason} ->
            Logger.error("Failed removing event store subscription: #{inspect(reason)}")
        end

      {:error, reason} ->
        Logger.error("Failed registering event store subscription: #{inspect(reason)}")
    end
  end

  defp showcase_read_models(account_id) do
    Logger.info("Showcasing Chronicle.ReadModels query APIs...")

    session_id = "console-sample-session-#{account_id}"

    case Chronicle.ReadModels.get_instance_by_id(Account, account_id, session_id: session_id) do
      {:ok, account} when not is_nil(account) ->
        Logger.info(
          "ReadModels.get_instance_by_id/3 returned #{account.account_id} with balance #{account.balance}"
        )

      {:ok, nil} ->
        Logger.warning("ReadModels.get_instance_by_id/3 returned nil")

      {:error, reason} ->
        Logger.error("ReadModels.get_instance_by_id/3 failed: #{inspect(reason)}")
    end

    case Chronicle.ReadModels.get(AccountSummary, account_id) do
      {:ok, summary} when not is_nil(summary) ->
        Logger.info(
          "ReadModels.get/3 returned reducer-backed AccountSummary with #{summary.transaction_count} transaction(s)"
        )

      {:ok, nil} ->
        Logger.warning("ReadModels.get/3 returned no AccountSummary yet")

      {:error, reason} ->
        Logger.error("ReadModels.get/3 for AccountSummary failed: #{inspect(reason)}")
    end

    case Chronicle.ReadModels.get_instances(Account, event_count: 100) do
      {:ok, accounts} ->
        Logger.info("ReadModels.get_instances/2 replayed #{length(accounts)} Account instance(s)")

      {:error, reason} ->
        Logger.error("ReadModels.get_instances/2 failed: #{inspect(reason)}")
    end

    case Chronicle.ReadModels.all(AccountSummary) do
      {:ok, summaries} ->
        Logger.info("ReadModels.all/2 replayed #{length(summaries)} AccountSummary instance(s)")

      {:error, reason} ->
        Logger.error("ReadModels.all/2 failed: #{inspect(reason)}")
    end

    case Chronicle.ReadModels.query(Account, page: 1, page_size: 10) do
      {:ok, result} ->
        Logger.info(
          "ReadModels.query/2 returned page #{result.page} with #{length(result.instances)} item(s) out of #{result.total_count}"
        )

      {:error, reason} ->
        Logger.error("ReadModels.query/2 failed: #{inspect(reason)}")
    end

    case Chronicle.ReadModels.get_snapshots_by_id(Account, account_id) do
      {:ok, snapshots} ->
        latest_snapshot = List.last(snapshots)

        Logger.info(
          "ReadModels.get_snapshots_by_id/3 returned #{length(snapshots)} snapshot(s)#{format_latest_snapshot(latest_snapshot)}"
        )

      {:error, reason} ->
        Logger.error("ReadModels.get_snapshots_by_id/3 failed: #{inspect(reason)}")
    end

    case Chronicle.ReadModels.occurrences(Account) do
      {:ok, occurrences} ->
        Logger.info("ReadModels.occurrences/2 returned #{length(occurrences)} occurrence(s)")

      {:error, reason} ->
        Logger.error("ReadModels.occurrences/2 failed: #{inspect(reason)}")
    end

    case Chronicle.ReadModels.definitions() do
      {:ok, definitions} ->
        matching_definitions =
          Enum.filter(definitions, fn definition ->
            definition.identifier in [
              Account.__chronicle_read_model__(:id),
              AccountSummary.__chronicle_read_model__(:id)
            ]
          end)

        Logger.info(
          "ReadModels.definitions/1 returned #{length(definitions)} definition(s); sample models: #{inspect(Enum.map(matching_definitions, &{&1.identifier, &1.observer_type}))}"
        )

      {:error, reason} ->
        Logger.error("ReadModels.definitions/1 failed: #{inspect(reason)}")
    end
  end

  defp format_latest_snapshot(nil), do: ""

  defp format_latest_snapshot(snapshot) do
    " (latest balance #{snapshot.read_model && snapshot.read_model.balance}, events #{length(snapshot.events)})"
  end

  defp append_with_concurrency_scope(account_id) do
    case Chronicle.get_tail_sequence_number(account_id) do
      {:ok, sequence_number} ->
        Logger.info("Building concurrency scope from tail sequence number #{sequence_number}...")

        scope = ConcurrencyScope.for_event_source(sequence_number)
        unit_of_work = UnitOfWork.begin()

        Logger.info("Buffering FundsDeposited and FundsWithdrawn in a unit of work...")

        :ok =
          Chronicle.append(account_id, %FundsDeposited{account_id: account_id, amount: 500},
            concurrency_scope: scope
          )

        :ok =
          Chronicle.append(account_id, %FundsWithdrawn{account_id: account_id, amount: 200},
            concurrency_scope: scope
          )

        Logger.info(
          "Committing unit of work #{UnitOfWork.correlation_id(unit_of_work).value} with buffered events..."
        )

        case UnitOfWork.commit(unit_of_work) do
          :ok -> Logger.info("Transactional commit succeeded")
          {:error, reason} -> Logger.error("Transactional commit failed: #{inspect(reason)}")
        end

      {:error, reason} ->
        Logger.error(
          "Failed getting tail sequence number for concurrency scope: #{inspect(reason)}"
        )
    end
  end
end
