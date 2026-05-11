# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Reducer do
  @moduledoc """
  Behaviour and macro for defining Chronicle reducers.

  Reducers build and maintain read models by folding events into state.
  Each event type that the reducer handles is applied in order, progressively
  updating the read model from its initial state.

  ## Defining a reducer

  Use `Chronicle.Reducer` in a module, declare which events it handles with
  `@handles`, and implement the `reduce/3` callback.

      defmodule MyApp.Reducers.AccountReducer do
        use Chronicle.Reducer, model: MyApp.ReadModels.Account

        @handles MyApp.Events.AccountOpened
        @handles MyApp.Events.FundsDeposited
        @handles MyApp.Events.FundsWithdrawn

        @impl true
        def reduce(%MyApp.Events.AccountOpened{} = event, _model, _context) do
          %MyApp.ReadModels.Account{
            account_id: event.account_id,
            owner_name: event.owner_name,
            balance: event.initial_balance
          }
        end

        def reduce(%MyApp.Events.FundsDeposited{} = event, model, _context) do
          %{model | balance: model.balance + event.amount}
        end

        def reduce(%MyApp.Events.FundsWithdrawn{} = event, model, _context) do
          %{model | balance: model.balance - event.amount}
        end
      end

  ## Options for `use Chronicle.Reducer`

    * `:model` — **(required)** the read model module this reducer produces.
    * `:id` — a stable string identifier. Defaults to the module's full name.

  ## Registering with Chronicle.Client

      {Chronicle.Client,
        ...
        reducers: [MyApp.Reducers.AccountReducer]}

  ## How reducers work

  When Chronicle needs the current state of a read model, it:

  1. Fetches the stored read model JSON (or starts with `nil`)
  2. Fetches all new events for the relevant event source
  3. Sends them to the reducer as a `ReduceOperationMessage`
  4. The reducer applies each event via `reduce/3` and returns the final state

  The model is stored by Chronicle between calls, so `reduce/3` only receives
  events that occurred since the last successful reduction.

  ## Event context

  The third argument to `reduce/3` is a map with:

    * `:event_source_id` — the event source (e.g. aggregate ID)
    * `:sequence_number` — the event's position in the event log
    * `:occurred` — when the event was appended (ISO 8601 string)
    * `:observation_state` — the observation state (`:initial`, `:replay`, etc.)
  """

  @doc """
  Applies an event to the current read model state.

  Receives the event struct, the current model (or `nil` on first event), and
  a context map. Returns the updated read model struct.
  """
  @callback reduce(event :: struct(), model :: struct() | nil, context :: map()) :: struct()

  defmacro __using__(opts) do
    model = Keyword.fetch!(opts, :model)

    quote bind_quoted: [opts: opts, model: model] do
      @behaviour Chronicle.Reducer

      Module.register_attribute(__MODULE__, :handles, accumulate: true)

      @chronicle_reducer_model model
      @chronicle_reducer_id Keyword.get(opts, :id, __MODULE__ |> to_string())

      @before_compile Chronicle.Reducer
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      @doc false
      def __chronicle_reducer__(:id), do: @chronicle_reducer_id
      def __chronicle_reducer__(:model), do: @chronicle_reducer_model
      def __chronicle_reducer__(:handles), do: @handles |> Enum.reverse()
    end
  end
end
