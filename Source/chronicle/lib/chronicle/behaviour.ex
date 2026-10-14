# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Behaviour do
  @moduledoc """
  Behaviour declaring the public API of the `Chronicle` facade.

  `Chronicle` adopts this behaviour (`@behaviour Chronicle.Behaviour`), so a
  test can generate a mock of it with [Mox](https://hex.pm/packages/mox)
  (not a dependency of this library — add it to your own `mix.exs`):

      Mox.defmock(MyApp.ChronicleMock, for: Chronicle.Behaviour)

  Then configure your application to call through the mock in tests, and
  stub whatever functions the code under test calls:

      Mox.expect(MyApp.ChronicleMock, :append, fn "account-1", %AccountOpened{}, _opts -> :ok end)

  Prefer `Chronicle.Testing.start_supervised_client/1` when the behavior under test
  should see real appends, reactors, reducers, constraints and concurrency checks;
  reach for a `Chronicle.Behaviour` mock when the code under test only needs to be
  observed calling the facade with the right arguments.
  """

  @callback append(String.t(), struct(), keyword()) :: :ok | {:error, term()}
  @callback append_many(String.t(), [struct()], keyword()) :: :ok | {:error, term()}
  @callback append_with_result(String.t(), struct(), keyword()) ::
              {:ok, Chronicle.EventSequences.AppendResult.t()}
              | {:error, Chronicle.EventSequences.AppendResult.t() | term()}
  @callback append_many_with_result(String.t(), [struct()], keyword()) ::
              {:ok, Chronicle.EventSequences.AppendResult.t()}
              | {:error, Chronicle.EventSequences.AppendResult.t() | term()}
  @callback event_sequence(String.t(), keyword()) :: Chronicle.EventSequences.EventSequence.t()
  @callback begin_unit_of_work(keyword()) :: Chronicle.Transactions.UnitOfWork.t()
  @callback current_unit_of_work() :: Chronicle.Transactions.UnitOfWork.t()
  @callback with_unit_of_work((Chronicle.Transactions.UnitOfWork.t() -> any()), keyword()) ::
              any()
  @callback read_model(module(), String.t(), keyword()) ::
              {:ok, struct() | nil} | {:error, term()}
  @callback all(module(), keyword()) :: {:ok, [struct()]} | {:error, term()}
  @callback get_event_stores(keyword()) :: {:ok, [String.t()]} | {:error, term()}
  @callback get_namespaces(keyword()) :: {:ok, [String.t()]} | {:error, term()}
  @callback get_tail_sequence_number(String.t() | nil, keyword()) ::
              {:ok, non_neg_integer()} | {:error, term()}
  @callback has_events_for?(String.t(), keyword()) :: {:ok, boolean()} | {:error, term()}
  @callback current_correlation_id() :: Chronicle.Correlation.CorrelationId.t()
  @callback set_correlation_id(Chronicle.Correlation.CorrelationId.t() | String.t()) ::
              Chronicle.Correlation.CorrelationId.t()
  @callback clear_correlation_id() :: Chronicle.Correlation.CorrelationId.t()
  @callback get_jobs(keyword()) :: {:ok, [Chronicle.Jobs.Job.t()]} | {:error, term()}
  @callback get_job(String.t(), keyword()) ::
              {:ok, Chronicle.Jobs.Job.t() | nil} | {:error, term()}
  @callback get_job_steps(String.t(), keyword()) ::
              {:ok, [Chronicle.Jobs.JobStep.t()]} | {:error, term()}
  @callback stop_job(String.t(), keyword()) :: :ok | {:error, term()}
  @callback resume_job(String.t(), keyword()) :: :ok | {:error, term()}
  @callback delete_job(String.t(), keyword()) :: :ok | {:error, term()}
  @callback get_webhooks(keyword()) ::
              {:ok, [Chronicle.WebHooks.Definition.t()]} | {:error, term()}
  @callback register_discovered_webhooks(keyword()) :: :ok | {:error, term()}
  @callback remove_webhook(String.t(), keyword()) :: :ok | {:error, term()}
  @callback register_webhook(module(), keyword()) :: :ok | {:error, term()}
  @callback register_webhook(
              String.t(),
              String.t(),
              (Chronicle.WebHooks.DefinitionBuilder.t() ->
                 Chronicle.WebHooks.DefinitionBuilder.t()),
              keyword()
            ) :: :ok | {:error, term()}
  @callback register_discovered_event_store_subscriptions(keyword()) :: :ok | {:error, term()}
  @callback register_event_store_subscription(module(), keyword()) :: :ok | {:error, term()}
  @callback subscribe_to_event_store(String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  @callback subscribe_to_event_store(
              String.t(),
              String.t(),
              (Chronicle.EventStoreSubscriptions.DefinitionBuilder.t() ->
                 Chronicle.EventStoreSubscriptions.DefinitionBuilder.t()),
              keyword()
            ) :: :ok | {:error, term()}
  @callback unsubscribe_from_event_store(String.t(), keyword()) :: :ok | {:error, term()}
  @callback current_identity() :: Chronicle.Identity.t()
  @callback set_identity(Chronicle.Identity.t()) :: Chronicle.Identity.t()
  @callback clear_identity() :: :ok
end
