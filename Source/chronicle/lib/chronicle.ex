# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle do
  @moduledoc """
  Idiomatic Elixir client for the Chronicle event-sourcing platform.

  Chronicle is an event-sourcing kernel that stores domain events and projects
  them into read models. This library provides an idiomatic Elixir interface
  built on top of the Chronicle gRPC API.

  ## Quick Start

  Add the dependency to your `mix.exs`:

      {:cratis_chronicle, "~> 0.1"}

  Start `Chronicle.Client` in your application supervision tree:

      defmodule MyApp.Application do
        use Application

        def start(_type, _args) do
          children = [
            {Chronicle.Client,
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

      {Chronicle.Client,
        connection_string: "chronicle://localhost:35000",
        event_store: "my-app",
        otp_app: :my_app}

  ## Defining Event Types

      defmodule MyApp.Events.AccountOpened do
        use Chronicle.Events.EventType, id: "account-opened-v1"
        defstruct [:account_id, :owner_name, :initial_balance]
      end

  ## Appending Events

      Chronicle.append("account-42", %MyApp.Events.AccountOpened{
        account_id: "account-42",
        owner_name: "Alice",
        initial_balance: 1000
      })

  ## Reading Read Models

      {:ok, account} = Chronicle.read_model(MyApp.ReadModels.Account, "account-42")

  ## Defining Reactors

      defmodule MyApp.Reactors.NotificationReactor do
        use Chronicle.Reactors.Reactor

        @handles MyApp.Events.AccountOpened

        @impl true
        def handle(%MyApp.Events.AccountOpened{} = event, _context) do
          MyApp.Mailer.welcome(event.owner_name)
          :ok
        end
      end

  ## Defining Reducers

      defmodule MyApp.Reducers.AccountReducer do
        use Chronicle.Reducers.Reducer, model: MyApp.ReadModels.Account

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
        use Chronicle.Seeding.Seeder

        @impl true
        def seed(builder) do
          builder
          |> Chronicle.Seeding.for(
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

    * `Chronicle.Client` — the main supervisor; start it in your supervision tree
    * `Chronicle.Correlation.CorrelationId` / `Chronicle.Correlation.CorrelationIdManager` — correlate operations
    * `Chronicle.Identity` / `Chronicle.Identity.IdentityProvider` — track who caused state changes
    * `Chronicle.Auditing.CausationType`, `Chronicle.Auditing.CausationEntry`, `Chronicle.Auditing.CausationManager` — audit causation chains
    * `Chronicle.Events.EventType` — macro for defining event types
    * `Chronicle.Events.Migration` — macro for defining event migrations
    * `Chronicle.Events.MigrationBuilder` — fluent API for migration transforms
    * `Chronicle.Events.Migrators` — migration discovery and registration support
    * `Chronicle.Events.ConcurrencyScope` — scope optimistic concurrency checks for appends
    * `Chronicle.Reactors.Reactor` — behaviour for event reactors
    * `Chronicle.Reducers.Reducer` — behaviour for read model reducers
    * `Chronicle.Seeding.Seeder` — behaviour for event seeders
    * `Chronicle.EventStoreSubscriptions` — register event store subscriptions
    * `Chronicle.EventStoreSubscriptions.Subscription` — define discoverable event store subscriptions
    * `Chronicle.ReadModels.ReadModel` — macro for read model structs with embedded projection DSL
    * `Chronicle.EventSequences.EventLog` — append and query events
    * `Chronicle.EventSequences.EventSequence` — work with custom event sequences
    * `Chronicle.Transactions.UnitOfWork` — buffer and commit transactional appends
    * `Chronicle.EventStores` — list event stores and namespaces
    * `Chronicle.ReadModels` — query read model instances
    * `Chronicle.Jobs` — inspect and control Chronicle jobs
    * `Chronicle.WebHooks` — inspect and register webhooks
    * `Chronicle.Connections.ConnectionString` — parse and format connection strings
    * `Chronicle.Connections.Connection` — resilient gRPC channel management
  """

  @doc """
  Appends a single event to the event log for the given event source.

  Delegates to `Chronicle.EventSequences.EventLog.append/3`.

  ## Options

    * `:client` — the client name (default: `Chronicle.Client`)
    * `:namespace` — overrides the client's default namespace
    * `:event_sequence_id` — event sequence id (default: `"event-log"`)
    * `:tags` — list of tag strings
    * `:subject` — the identity subject string
    * `:correlation_id` — `Chronicle.Correlation.CorrelationId` (or id string) override
    * `:identity` — `Chronicle.Identity` override
    * `:causation` — list of `Chronicle.Auditing.CausationEntry` overrides
    * `:concurrency_scope` — `Chronicle.Events.ConcurrencyScope` or keyword options
  """
  @spec append(String.t(), struct(), keyword()) :: :ok | {:error, term()}
  defdelegate append(event_source_id, event, opts \\ []), to: Chronicle.EventSequences.EventLog

  @doc """
  Appends multiple events to the event log for the given event source.

  Delegates to `Chronicle.EventSequences.EventLog.append_many/3`.
  Accepts the same append options as `append/3`, including `:concurrency_scope`.
  """
  @spec append_many(String.t(), [struct()], keyword()) :: :ok | {:error, term()}
  defdelegate append_many(event_source_id, events, opts \\ []),
    to: Chronicle.EventSequences.EventLog

  @doc """
  Creates an event sequence wrapper for the given event sequence id.
  """
  @spec event_sequence(String.t(), keyword()) :: Chronicle.EventSequences.EventSequence.t()
  defdelegate event_sequence(event_sequence_id, opts \\ []),
    to: Chronicle.EventSequences.EventSequence,
    as: :new

  @doc """
  Begins a new unit of work for the calling process.
  """
  @spec begin_unit_of_work(keyword()) :: Chronicle.Transactions.UnitOfWork.t()
  defdelegate begin_unit_of_work(opts \\ []), to: Chronicle.Transactions.UnitOfWork, as: :begin

  @doc """
  Returns the current unit of work for the calling process.
  """
  @spec current_unit_of_work() :: Chronicle.Transactions.UnitOfWork.t()
  defdelegate current_unit_of_work(), to: Chronicle.Transactions.UnitOfWork, as: :current

  @doc """
  Runs a function inside a unit of work and commits it if the function succeeds.
  """
  @spec with_unit_of_work((Chronicle.Transactions.UnitOfWork.t() -> any()), keyword()) :: any()
  defdelegate with_unit_of_work(fun, opts \\ []), to: Chronicle.Transactions.UnitOfWork

  @doc """
  Fetches a read model instance by its key (typically an event source ID).

  Delegates to `Chronicle.ReadModels.get/3`.

  Returns `{:ok, model_struct}` on success, or `{:ok, nil}` if not found.
  """
  @spec read_model(module(), String.t(), keyword()) :: {:ok, struct() | nil} | {:error, term()}
  defdelegate read_model(model_module, key, opts \\ []), to: Chronicle.ReadModels, as: :get

  @doc """
  Returns all instances of the given read model.

  Delegates to `Chronicle.ReadModels.all/2`.
  """
  @spec all(module(), keyword()) :: {:ok, [struct()]} | {:error, term()}
  defdelegate all(model_module, opts \\ []), to: Chronicle.ReadModels

  @doc """
  Returns all event store names.
  """
  @spec get_event_stores(keyword()) :: {:ok, [String.t()]} | {:error, term()}
  defdelegate get_event_stores(opts \\ []), to: Chronicle.EventStores, as: :get_all

  @doc """
  Returns all namespaces for an event store.

  Uses the configured client event store by default.
  """
  @spec get_namespaces(keyword()) :: {:ok, [String.t()]} | {:error, term()}
  defdelegate get_namespaces(opts \\ []), to: Chronicle.EventStores

  @doc """
  Gets the tail sequence number for an event sequence.
  """
  @spec get_tail_sequence_number(String.t() | nil, keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  defdelegate get_tail_sequence_number(event_source_id \\ nil, opts \\ []),
    to: Chronicle.EventSequences.EventLog

  @doc """
  Checks whether there are events for an event source id in an event sequence.
  """
  @spec has_events_for?(String.t(), keyword()) :: {:ok, boolean()} | {:error, term()}
  defdelegate has_events_for?(event_source_id, opts \\ []), to: Chronicle.EventSequences.EventLog

  @doc """
  Gets the current process correlation id.
  """
  @spec current_correlation_id() :: Chronicle.Correlation.CorrelationId.t()
  defdelegate current_correlation_id(),
    to: Chronicle.Correlation.CorrelationIdManager,
    as: :current

  @doc """
  Sets the current process correlation id.
  """
  @spec set_correlation_id(Chronicle.Correlation.CorrelationId.t() | String.t()) ::
          Chronicle.Correlation.CorrelationId.t()
  defdelegate set_correlation_id(correlation_id),
    to: Chronicle.Correlation.CorrelationIdManager,
    as: :set_current

  @doc """
  Clears the current process correlation id.
  """
  @spec clear_correlation_id() :: Chronicle.Correlation.CorrelationId.t()
  defdelegate clear_correlation_id(), to: Chronicle.Correlation.CorrelationIdManager, as: :clear

  @doc """
  Gets all jobs for the configured event store namespace.
  """
  @spec get_jobs(keyword()) :: {:ok, [Chronicle.Jobs.Job.t()]} | {:error, term()}
  defdelegate get_jobs(opts \\ []), to: Chronicle.Jobs, as: :all

  @doc """
  Gets a single Chronicle job by identifier.
  """
  @spec get_job(String.t(), keyword()) :: {:ok, Chronicle.Jobs.Job.t() | nil} | {:error, term()}
  defdelegate get_job(job_id, opts \\ []), to: Chronicle.Jobs, as: :get

  @doc """
  Gets all steps for a Chronicle job.
  """
  @spec get_job_steps(String.t(), keyword()) ::
          {:ok, [Chronicle.Jobs.JobStep.t()]} | {:error, term()}
  defdelegate get_job_steps(job_id, opts \\ []), to: Chronicle.Jobs, as: :steps

  @doc """
  Stops a Chronicle job.
  """
  @spec stop_job(String.t(), keyword()) :: :ok | {:error, term()}
  defdelegate stop_job(job_id, opts \\ []), to: Chronicle.Jobs, as: :stop

  @doc """
  Resumes a Chronicle job.
  """
  @spec resume_job(String.t(), keyword()) :: :ok | {:error, term()}
  defdelegate resume_job(job_id, opts \\ []), to: Chronicle.Jobs, as: :resume

  @doc """
  Deletes a Chronicle job.
  """
  @spec delete_job(String.t(), keyword()) :: :ok | {:error, term()}
  defdelegate delete_job(job_id, opts \\ []), to: Chronicle.Jobs, as: :delete

  @doc """
  Gets all registered webhooks.
  """
  @spec get_webhooks(keyword()) :: {:ok, [Chronicle.WebHooks.Definition.t()]} | {:error, term()}
  defdelegate get_webhooks(opts \\ []), to: Chronicle.WebHooks, as: :all

  @doc """
  Registers all discoverable webhooks.
  """
  @spec register_discovered_webhooks(keyword()) :: :ok | {:error, term()}
  defdelegate register_discovered_webhooks(opts \\ []),
    to: Chronicle.WebHooks,
    as: :register_discovered

  @doc """
  Removes a registered webhook by identifier.
  """
  @spec remove_webhook(String.t(), keyword()) :: :ok | {:error, term()}
  defdelegate remove_webhook(webhook_id, opts \\ []), to: Chronicle.WebHooks, as: :remove

  @doc """
  Registers a discoverable webhook module.
  """
  @spec register_webhook(module(), keyword()) :: :ok | {:error, term()}
  def register_webhook(webhook_module, opts \\ [])
      when is_atom(webhook_module) and is_list(opts) do
    Chronicle.WebHooks.register(webhook_module, opts)
  end

  @doc """
  Registers a webhook imperatively.
  """
  @spec register_webhook(
          String.t(),
          String.t(),
          (Chronicle.WebHooks.DefinitionBuilder.t() -> Chronicle.WebHooks.DefinitionBuilder.t()),
          keyword()
        ) ::
          :ok | {:error, term()}
  def register_webhook(webhook_id, target_url, configure, opts \\ []) do
    Chronicle.WebHooks.register(webhook_id, target_url, configure, opts)
  end

  @doc """
  Registers all discoverable event store subscriptions.
  """
  @spec register_discovered_event_store_subscriptions(keyword()) :: :ok | {:error, term()}
  defdelegate register_discovered_event_store_subscriptions(opts \\ []),
    to: Chronicle.EventStoreSubscriptions,
    as: :register_discovered

  @doc """
  Registers a discoverable event store subscription module.
  """
  @spec register_event_store_subscription(module(), keyword()) :: :ok | {:error, term()}
  def register_event_store_subscription(subscription_module, opts \\ [])
      when is_atom(subscription_module) and is_list(opts) do
    Chronicle.EventStoreSubscriptions.register(subscription_module, opts)
  end

  @doc """
  Registers an event store subscription imperatively using all available event
  types.
  """
  @spec subscribe_to_event_store(String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def subscribe_to_event_store(subscription_id, source_event_store, opts)
      when is_binary(subscription_id) and is_binary(source_event_store) and is_list(opts) do
    Chronicle.EventStoreSubscriptions.subscribe(subscription_id, source_event_store, opts)
  end

  @doc """
  Registers an event store subscription imperatively.
  """
  @spec subscribe_to_event_store(
          String.t(),
          String.t(),
          (Chronicle.EventStoreSubscriptions.DefinitionBuilder.t() ->
             Chronicle.EventStoreSubscriptions.DefinitionBuilder.t()),
          keyword()
        ) :: :ok | {:error, term()}
  def subscribe_to_event_store(subscription_id, source_event_store, configure, opts \\ []) do
    Chronicle.EventStoreSubscriptions.subscribe(
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
    to: Chronicle.EventStoreSubscriptions,
    as: :unsubscribe

  @doc """
  Gets the current process identity.
  """
  @spec current_identity() :: Chronicle.Identity.t()
  defdelegate current_identity(), to: Chronicle.Identity.IdentityProvider, as: :get_current

  @doc """
  Sets the current process identity.
  """
  @spec set_identity(Chronicle.Identity.t()) :: Chronicle.Identity.t()
  defdelegate set_identity(identity),
    to: Chronicle.Identity.IdentityProvider,
    as: :set_current_identity

  @doc """
  Clears the current process identity.
  """
  @spec clear_identity() :: :ok
  defdelegate clear_identity(),
    to: Chronicle.Identity.IdentityProvider,
    as: :clear_current_identity
end
