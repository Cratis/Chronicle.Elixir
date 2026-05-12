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
              reducers: [MyApp.Reducers.AccountReducer]}
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

  ## Modules

    * `Chronicle.Client` — the main supervisor; start it in your supervision tree
    * `Chronicle.EventType` — macro for defining event types
    * `Chronicle.Reactor` — behaviour for event reactors
    * `Chronicle.Reducer` — behaviour for read model reducers
    * `Chronicle.ReadModel` — macro for read model structs with embedded projection DSL
    * `Chronicle.EventLog` — append and query events
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
    * `:tags` — list of tag strings
    * `:subject` — the identity subject string
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
end
