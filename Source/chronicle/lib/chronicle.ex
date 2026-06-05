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
              connection_string: "chronicle://localhost:35000?disableTls=true",
              event_store: "my-app",
              event_types: [MyApp.Events.AccountOpened, MyApp.Events.FundsDeposited],
              reactors: [MyApp.Reactors.NotificationReactor],
              reducers: [MyApp.Reducers.AccountReducer],
              seeders: [MyApp.Seeders.InitialDataSeeder]}
          ]

          Supervisor.start_link(children, strategy: :one_for_one)
        end
      end

  Or rely on artifact auto-discovery:

      {Chronicle.Client,
        connection_string: "chronicle://localhost:35000?disableTls=true",
        event_store: "my-app",
        otp_app: :my_app}

  ## Defining Event Types

      defmodule MyApp.Events.AccountOpened do
        use Chronicle.EventType, id: "account-opened-v1"
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
        use Chronicle.Reactor

        @handles MyApp.Events.AccountOpened

        @impl true
        def handle(%MyApp.Events.AccountOpened{} = event, _context) do
          MyApp.Mailer.welcome(event.owner_name)
          :ok
        end
      end

  ## Defining Reducers

      defmodule MyApp.Reducers.AccountReducer do
        use Chronicle.Reducer, model: MyApp.ReadModels.Account

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
        use Chronicle.Seeder

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
    * `Chronicle.CorrelationId` / `Chronicle.CorrelationIdManager` — correlate operations
    * `Chronicle.Identity` / `Chronicle.IdentityProvider` — track who caused state changes
    * `Chronicle.CausationType`, `Chronicle.CausationEntry`, `Chronicle.CausationManager` — audit causation chains
    * `Chronicle.EventType` — macro for defining event types
    * `Chronicle.Reactor` — behaviour for event reactors
    * `Chronicle.Reducer` — behaviour for read model reducers
    * `Chronicle.Seeder` — behaviour for event seeders
    * `Chronicle.ReadModel` — macro for read model structs with embedded projection DSL
    * `Chronicle.EventLog` — append and query events
    * `Chronicle.EventStores` — list event stores and namespaces
    * `Chronicle.ReadModels` — query read model instances
    * `Chronicle.Connections.ConnectionString` — parse and format connection strings
    * `Chronicle.Connections.Connection` — resilient gRPC channel management
  """

  @doc """
  Appends a single event to the event log for the given event source.

  Delegates to `Chronicle.EventLog.append/3`.

  ## Options

    * `:client` — the client name (default: `Chronicle.Client`)
    * `:namespace` — overrides the client's default namespace
    * `:event_sequence_id` — event sequence id (default: `"event-log"`)
    * `:tags` — list of tag strings
    * `:subject` — the identity subject string
    * `:correlation_id` — `Chronicle.CorrelationId` (or id string) override
    * `:identity` — `Chronicle.Identity` override
    * `:causation` — list of `Chronicle.CausationEntry` overrides
  """
  @spec append(String.t(), struct(), keyword()) :: :ok | {:error, term()}
  defdelegate append(event_source_id, event, opts \\ []), to: Chronicle.EventLog

  @doc """
  Appends multiple events to the event log for the given event source.

  Delegates to `Chronicle.EventLog.append_many/3`.
  """
  @spec append_many(String.t(), [struct()], keyword()) :: :ok | {:error, term()}
  defdelegate append_many(event_source_id, events, opts \\ []), to: Chronicle.EventLog

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
  defdelegate get_tail_sequence_number(event_source_id \\ nil, opts \\ []), to: Chronicle.EventLog

  @doc """
  Checks whether there are events for an event source id in an event sequence.
  """
  @spec has_events_for?(String.t(), keyword()) :: {:ok, boolean()} | {:error, term()}
  defdelegate has_events_for?(event_source_id, opts \\ []), to: Chronicle.EventLog

  @doc """
  Gets the current process correlation id.
  """
  @spec current_correlation_id() :: Chronicle.CorrelationId.t()
  defdelegate current_correlation_id(), to: Chronicle.CorrelationIdManager, as: :current

  @doc """
  Sets the current process correlation id.
  """
  @spec set_correlation_id(Chronicle.CorrelationId.t() | String.t()) :: Chronicle.CorrelationId.t()
  defdelegate set_correlation_id(correlation_id), to: Chronicle.CorrelationIdManager, as: :set_current

  @doc """
  Clears the current process correlation id.
  """
  @spec clear_correlation_id() :: Chronicle.CorrelationId.t()
  defdelegate clear_correlation_id(), to: Chronicle.CorrelationIdManager, as: :clear

  @doc """
  Gets the current process identity.
  """
  @spec current_identity() :: Chronicle.Identity.t()
  defdelegate current_identity(), to: Chronicle.IdentityProvider, as: :get_current

  @doc """
  Sets the current process identity.
  """
  @spec set_identity(Chronicle.Identity.t()) :: Chronicle.Identity.t()
  defdelegate set_identity(identity), to: Chronicle.IdentityProvider, as: :set_current_identity

  @doc """
  Clears the current process identity.
  """
  @spec clear_identity() :: :ok
  defdelegate clear_identity(), to: Chronicle.IdentityProvider, as: :clear_current_identity
end
