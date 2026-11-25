# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Cratis.Chronicle do
  @behaviour Cratis.Chronicle.Behaviour

  @moduledoc """
  Idiomatic Elixir client for the Chronicle event-sourcing platform.

  Chronicle is an event-sourcing kernel that stores domain events and projects
  them into read models. This library provides an idiomatic Elixir interface
  built on top of the Chronicle gRPC API.

  ## Quick Start

  Add the dependency to your `mix.exs`:

      {:cratis_chronicle, "~> 3.5"}

  Start `Cratis.Chronicle.Client` in your application supervision tree:

      defmodule MyApp.Application do
        use Application

        def start(_type, _args) do
          children = [
            {Cratis.Chronicle.Client,
              connection_string: "chronicle://localhost:35000",
              event_store: "my-app",
              event_types: [MyApp.Events.AccountOpened, MyApp.Events.FundsDeposited],
              migrations: [MyApp.Migrations.AccountOpenedV2Migration],
              reactors: [MyApp.Reactors.NotificationReactor],
              reducers: [MyApp.Reducers.AccountReducer],
              seeders: [MyApp.Seeders.InitialDataSeeder],
              event_store_subscriptions: [
                MyApp.EventStoreSubscriptions.DefaultAccountEvents
              ]}
          ]

          Supervisor.start_link(children, strategy: :one_for_one)
        end
      end

  Or rely on artifact auto-discovery:

      {Cratis.Chronicle.Client,
        connection_string: "chronicle://localhost:35000",
        event_store: "my-app",
        otp_app: :my_app}

  ## Defining Event Types

      defmodule MyApp.Events.AccountOpened do
        use Cratis.Chronicle.Events.EventType, id: "account-opened-v1"
        defstruct account_id: "", owner_name: "", initial_balance: 0
      end

  ## Appending Events

      Cratis.Chronicle.append("account-42", %MyApp.Events.AccountOpened{
        account_id: "account-42",
        owner_name: "Alice",
        initial_balance: 1000
      })

  ## Reading Read Models

      {:ok, account} = Cratis.Chronicle.read_model(MyApp.ReadModels.Account, "account-42")

  ## Defining Reactors

      defmodule MyApp.Reactors.NotificationReactor do
        use Cratis.Chronicle.Reactors.Reactor

        @handles MyApp.Events.AccountOpened

        @impl true
        def handle(%MyApp.Events.AccountOpened{} = event, _context) do
          MyApp.Mailer.welcome(event.owner_name)
          :ok
        end
      end

  ## Defining Reducers

      defmodule MyApp.Reducers.AccountReducer do
        use Cratis.Chronicle.Reducers.Reducer, model: MyApp.ReadModels.Account

        @handles MyApp.Events.AccountOpened

        @impl true
        def reduce(%MyApp.Events.AccountOpened{} = event, _model, _context) do
          %MyApp.ReadModels.Account{
            account_id: event.account_id,
            owner_name: event.owner_name,
            balance: event.initial_balance
          }
        end
      end

  ## Defining Seeders

      defmodule MyApp.Seeders.InitialDataSeeder do
        use Cratis.Chronicle.Seeding.Seeder

        @impl true
        def seed(builder) do
          builder
          |> Cratis.Chronicle.Seeding.for(
            MyApp.Events.AccountOpened,
            "seed-account-1",
            [%MyApp.Events.AccountOpened{
              account_id: "seed-account-1",
              owner_name: "Initial User",
              initial_balance: 10_000
            }]
          )
        end
      end

  ## Modules

    * `Cratis.Chronicle.Client` — the main supervisor; start it in your supervision tree
    * `Cratis.Chronicle.Correlation.CorrelationId` / `Cratis.Chronicle.Correlation.CorrelationIdManager` — correlate operations
    * `Cratis.Chronicle.Identity` / `Cratis.Chronicle.Identity.IdentityProvider` — track who caused state changes
    * `Cratis.Chronicle.Auditing.CausationType`, `Cratis.Chronicle.Auditing.CausationEntry`, `Cratis.Chronicle.Auditing.CausationManager` — audit causation chains
    * `Cratis.Chronicle.Events.EventType` — macro for defining event types
    * `Cratis.Chronicle.Events.Migration` — macro for defining event migrations
    * `Cratis.Chronicle.Events.MigrationBuilder` — fluent API for migration transforms
    * `Cratis.Chronicle.Events.Migrators` — migration discovery and registration support
    * `Cratis.Chronicle.Events.ConcurrencyScope` — scope optimistic concurrency checks for appends
    * `Cratis.Chronicle.Reactors.Reactor` — behaviour for event reactors
    * `Cratis.Chronicle.Reducers.Reducer` — behaviour for read model reducers
    * `Cratis.Chronicle.Seeding.Seeder` — behaviour for event seeders
    * `Cratis.Chronicle.EventStoreSubscriptions` — register event store subscriptions
    * `Cratis.Chronicle.EventStoreSubscriptions.Subscription` — define discoverable event store subscriptions
    * `Cratis.Chronicle.ReadModels.ReadModel` — macro for read model structs with embedded projection DSL
    * `Cratis.Chronicle.EventSequences.EventLog` — append and query events
    * `Cratis.Chronicle.EventSequences.EventSequence` — work with custom event sequences
    * `Cratis.Chronicle.Transactions.UnitOfWork` — buffer and commit transactional appends
    * `Cratis.Chronicle.EventStores` — list event stores and namespaces
    * `Cratis.Chronicle.ReadModels` — query read model instances
    * `Cratis.Chronicle.Jobs` — inspect and control Chronicle jobs
    * `Cratis.Chronicle.WebHooks` — inspect and register webhooks
    * `Cratis.Chronicle.Connections.ConnectionString` — parse and format connection strings
    * `Cratis.Chronicle.Connections.Connection` — resilient gRPC channel management
  """

  @doc """
  Appends a single event to the event log for the given event source.

  Delegates to `Cratis.Chronicle.EventSequences.EventLog.append/3`.

  ## Options

    * `:client` — the client name (default: `Cratis.Chronicle.Client`)
    * `:namespace` — overrides the client's default namespace
    * `:event_sequence_id` — event sequence id (default: `"event-log"`)
    * `:tags` — list of tag strings
    * `:subject` — the identity subject string
    * `:correlation_id` — `Cratis.Chronicle.Correlation.CorrelationId` (or id string) override
    * `:identity` — `Cratis.Chronicle.Identity` override
    * `:causation` — list of `Cratis.Chronicle.Auditing.CausationEntry` overrides
    * `:concurrency_scope` — `Cratis.Chronicle.Events.ConcurrencyScope` or keyword options
  """
  @spec append(String.t(), struct(), keyword()) :: :ok | {:error, term()}
  defdelegate append(event_source_id, event, opts \\ []),
    to: Cratis.Chronicle.EventSequences.EventLog

  @doc """
  Appends multiple events to the event log for the given event source.

  Delegates to `Cratis.Chronicle.EventSequences.EventLog.append_many/3`.
  Accepts the same append options as `append/3`, including `:concurrency_scope`.
  """
  @spec append_many(String.t(), [struct()], keyword()) :: :ok | {:error, term()}
  defdelegate append_many(event_source_id, events, opts \\ []),
    to: Cratis.Chronicle.EventSequences.EventLog

  @doc """
  Appends a single event and returns the detailed `Cratis.Chronicle.EventSequences.AppendResult`
  (assigned sequence number, structured constraint and concurrency violations).

  Delegates to `Cratis.Chronicle.EventSequences.EventLog.append_with_result/3`.
  """
  @spec append_with_result(String.t(), struct(), keyword()) ::
          {:ok, Cratis.Chronicle.EventSequences.AppendResult.t()}
          | {:error, Cratis.Chronicle.EventSequences.AppendResult.t() | term()}
  defdelegate append_with_result(event_source_id, event, opts \\ []),
    to: Cratis.Chronicle.EventSequences.EventLog

  @doc """
  Appends events atomically and returns the detailed `Cratis.Chronicle.EventSequences.AppendResult`.

  Delegates to `Cratis.Chronicle.EventSequences.EventLog.append_many_with_result/3`.
  """
  @spec append_many_with_result(String.t(), [struct()], keyword()) ::
          {:ok, Cratis.Chronicle.EventSequences.AppendResult.t()}
          | {:error, Cratis.Chronicle.EventSequences.AppendResult.t() | term()}
  defdelegate append_many_with_result(event_source_id, events, opts \\ []),
    to: Cratis.Chronicle.EventSequences.EventLog

  @doc """
  Creates an event sequence wrapper for the given event sequence id.
  """
  @spec event_sequence(String.t(), keyword()) :: Cratis.Chronicle.EventSequences.EventSequence.t()
  defdelegate event_sequence(event_sequence_id, opts \\ []),
    to: Cratis.Chronicle.EventSequences.EventSequence,
    as: :new

  @doc """
  Begins a new unit of work for the calling process.
  """
  @spec begin_unit_of_work(keyword()) :: Cratis.Chronicle.Transactions.UnitOfWork.t()
  defdelegate begin_unit_of_work(opts \\ []),
    to: Cratis.Chronicle.Transactions.UnitOfWork,
    as: :begin

  @doc """
  Returns the current unit of work for the calling process.
  """
  @spec current_unit_of_work() :: Cratis.Chronicle.Transactions.UnitOfWork.t()
  defdelegate current_unit_of_work(), to: Cratis.Chronicle.Transactions.UnitOfWork, as: :current

  @doc """
  Runs a function inside a unit of work and commits it if the function succeeds.
  """
  @spec with_unit_of_work((Cratis.Chronicle.Transactions.UnitOfWork.t() -> any()), keyword()) ::
          any()
  defdelegate with_unit_of_work(fun, opts \\ []), to: Cratis.Chronicle.Transactions.UnitOfWork

  @doc """
  Runs a function inside a unit of work and commits it, returning `{:ok, result}` on success or
  `{:error, %Cratis.Chronicle.ReadModels.DecisionConflict{}}` when a decision read enrolled in it
  (`Cratis.Chronicle.ReadModels.DecisionReads.get/3`) conflicted with a concurrent append. See
  `Cratis.Chronicle.Transactions.UnitOfWork.decide/2`.
  """
  @spec decide((Cratis.Chronicle.Transactions.UnitOfWork.t() -> result), keyword()) ::
          {:ok, result} | {:error, term()}
        when result: any()
  defdelegate decide(fun, opts \\ []), to: Cratis.Chronicle.Transactions.UnitOfWork

  @doc """
  Fetches a read model instance by its key (typically an event source ID).

  Delegates to `Cratis.Chronicle.ReadModels.get/3`.

  Returns `{:ok, model_struct}` on success, or `{:ok, nil}` if not found.
  """
  @spec read_model(module(), String.t(), keyword()) :: {:ok, struct() | nil} | {:error, term()}
  defdelegate read_model(model_module, key, opts \\ []), to: Cratis.Chronicle.ReadModels, as: :get

  @doc """
  Returns all instances of the given read model.

  Delegates to `Cratis.Chronicle.ReadModels.all/2`.
  """
  @spec all(module(), keyword()) :: {:ok, [struct()]} | {:error, term()}
  defdelegate all(model_module, opts \\ []), to: Cratis.Chronicle.ReadModels

  @doc """
  Returns all event store names.
  """
  @spec get_event_stores(keyword()) :: {:ok, [String.t()]} | {:error, term()}
  defdelegate get_event_stores(opts \\ []), to: Cratis.Chronicle.EventStores, as: :get_all

  @doc """
  Returns all namespaces for an event store.

  Uses the configured client event store by default.
  """
  @spec get_namespaces(keyword()) :: {:ok, [String.t()]} | {:error, term()}
  defdelegate get_namespaces(opts \\ []), to: Cratis.Chronicle.EventStores

  @doc """
  Gets the tail sequence number for an event sequence.
  """
  @spec get_tail_sequence_number(String.t() | nil, keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  defdelegate get_tail_sequence_number(event_source_id \\ nil, opts \\ []),
    to: Cratis.Chronicle.EventSequences.EventLog

  @doc """
  Checks whether there are events for an event source id in an event sequence.
  """
  @spec has_events_for?(String.t(), keyword()) :: {:ok, boolean()} | {:error, term()}
  defdelegate has_events_for?(event_source_id, opts \\ []),
    to: Cratis.Chronicle.EventSequences.EventLog

  @doc """
  Gets the current process correlation id.
  """
  @spec current_correlation_id() :: Cratis.Chronicle.Correlation.CorrelationId.t()
  defdelegate current_correlation_id(),
    to: Cratis.Chronicle.Correlation.CorrelationIdManager,
    as: :current

  @doc """
  Sets the current process correlation id.
  """
  @spec set_correlation_id(Cratis.Chronicle.Correlation.CorrelationId.t() | String.t()) ::
          Cratis.Chronicle.Correlation.CorrelationId.t()
  defdelegate set_correlation_id(correlation_id),
    to: Cratis.Chronicle.Correlation.CorrelationIdManager,
    as: :set_current

  @doc """
  Clears the current process correlation id.
  """
  @spec clear_correlation_id() :: Cratis.Chronicle.Correlation.CorrelationId.t()
  defdelegate clear_correlation_id(),
    to: Cratis.Chronicle.Correlation.CorrelationIdManager,
    as: :clear

  @doc """
  Gets all jobs for the configured event store namespace.
  """
  @spec get_jobs(keyword()) :: {:ok, [Cratis.Chronicle.Jobs.Job.t()]} | {:error, term()}
  defdelegate get_jobs(opts \\ []), to: Cratis.Chronicle.Jobs, as: :all

  @doc """
  Gets a single Chronicle job by identifier.
  """
  @spec get_job(String.t(), keyword()) ::
          {:ok, Cratis.Chronicle.Jobs.Job.t() | nil} | {:error, term()}
  defdelegate get_job(job_id, opts \\ []), to: Cratis.Chronicle.Jobs, as: :get

  @doc """
  Gets all steps for a Chronicle job.
  """
  @spec get_job_steps(String.t(), keyword()) ::
          {:ok, [Cratis.Chronicle.Jobs.JobStep.t()]} | {:error, term()}
  defdelegate get_job_steps(job_id, opts \\ []), to: Cratis.Chronicle.Jobs, as: :steps

  @doc """
  Stops a Chronicle job.
  """
  @spec stop_job(String.t(), keyword()) :: :ok | {:error, term()}
  defdelegate stop_job(job_id, opts \\ []), to: Cratis.Chronicle.Jobs, as: :stop

  @doc """
  Resumes a Chronicle job.
  """
  @spec resume_job(String.t(), keyword()) :: :ok | {:error, term()}
  defdelegate resume_job(job_id, opts \\ []), to: Cratis.Chronicle.Jobs, as: :resume

  @doc """
  Deletes a Chronicle job.
  """
  @spec delete_job(String.t(), keyword()) :: :ok | {:error, term()}
  defdelegate delete_job(job_id, opts \\ []), to: Cratis.Chronicle.Jobs, as: :delete

  @doc """
  Gets all registered webhooks.
  """
  @spec get_webhooks(keyword()) ::
          {:ok, [Cratis.Chronicle.WebHooks.Definition.t()]} | {:error, term()}
  defdelegate get_webhooks(opts \\ []), to: Cratis.Chronicle.WebHooks, as: :all

  @doc """
  Registers all discoverable webhooks.
  """
  @spec register_discovered_webhooks(keyword()) :: :ok | {:error, term()}
  defdelegate register_discovered_webhooks(opts \\ []),
    to: Cratis.Chronicle.WebHooks,
    as: :register_discovered

  @doc """
  Removes a registered webhook by identifier.
  """
  @spec remove_webhook(String.t(), keyword()) :: :ok | {:error, term()}
  defdelegate remove_webhook(webhook_id, opts \\ []), to: Cratis.Chronicle.WebHooks, as: :remove

  @doc """
  Registers a discoverable webhook module.
  """
  @spec register_webhook(module(), keyword()) :: :ok | {:error, term()}
  def register_webhook(webhook_module, opts \\ [])
      when is_atom(webhook_module) and is_list(opts) do
    Cratis.Chronicle.WebHooks.register(webhook_module, opts)
  end

  @doc """
  Registers a webhook imperatively.
  """
  @spec register_webhook(
          String.t(),
          String.t(),
          (Cratis.Chronicle.WebHooks.DefinitionBuilder.t() ->
             Cratis.Chronicle.WebHooks.DefinitionBuilder.t()),
          keyword()
        ) ::
          :ok | {:error, term()}
  def register_webhook(webhook_id, target_url, configure, opts \\ []) do
    Cratis.Chronicle.WebHooks.register(webhook_id, target_url, configure, opts)
  end

  @doc """
  Registers all discoverable event store subscriptions.
  """
  @spec register_discovered_event_store_subscriptions(keyword()) :: :ok | {:error, term()}
  defdelegate register_discovered_event_store_subscriptions(opts \\ []),
    to: Cratis.Chronicle.EventStoreSubscriptions,
    as: :register_discovered

  @doc """
  Registers a discoverable event store subscription module.
  """
  @spec register_event_store_subscription(module(), keyword()) :: :ok | {:error, term()}
  def register_event_store_subscription(subscription_module, opts \\ [])
      when is_atom(subscription_module) and is_list(opts) do
    Cratis.Chronicle.EventStoreSubscriptions.register(subscription_module, opts)
  end

  @doc """
  Registers an event store subscription imperatively using all available event
  types.
  """
  @spec subscribe_to_event_store(String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def subscribe_to_event_store(subscription_id, source_event_store, opts)
      when is_binary(subscription_id) and is_binary(source_event_store) and is_list(opts) do
    Cratis.Chronicle.EventStoreSubscriptions.subscribe(subscription_id, source_event_store, opts)
  end

  @doc """
  Registers an event store subscription imperatively.
  """
  @spec subscribe_to_event_store(
          String.t(),
          String.t(),
          (Cratis.Chronicle.EventStoreSubscriptions.DefinitionBuilder.t() ->
             Cratis.Chronicle.EventStoreSubscriptions.DefinitionBuilder.t()),
          keyword()
        ) :: :ok | {:error, term()}
  def subscribe_to_event_store(subscription_id, source_event_store, configure, opts \\ []) do
    Cratis.Chronicle.EventStoreSubscriptions.subscribe(
      subscription_id,
      source_event_store,
      configure,
      opts
    )
  end

  @doc """
  Removes an event store subscription by identifier.
  """
  @spec unsubscribe_from_event_store(String.t(), keyword()) :: :ok | {:error, term()}
  defdelegate unsubscribe_from_event_store(subscription_id, opts \\ []),
    to: Cratis.Chronicle.EventStoreSubscriptions,
    as: :unsubscribe

  @doc """
  Gets the current process identity.
  """
  @spec current_identity() :: Cratis.Chronicle.Identity.t()
  defdelegate current_identity(), to: Cratis.Chronicle.Identity.IdentityProvider, as: :get_current

  @doc """
  Sets the current process identity.
  """
  @spec set_identity(Cratis.Chronicle.Identity.t()) :: Cratis.Chronicle.Identity.t()
  defdelegate set_identity(identity),
    to: Cratis.Chronicle.Identity.IdentityProvider,
    as: :set_current_identity

  @doc """
  Clears the current process identity.
  """
  @spec clear_identity() :: :ok
  defdelegate clear_identity(),
    to: Cratis.Chronicle.Identity.IdentityProvider,
    as: :clear_current_identity
end
