# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.ReadModel do
  @moduledoc """
  Macro for defining Chronicle read models with embedded model-bound projections.

  Use `Chronicle.ReadModel` in a struct module to define both the read model
  shape and how Chronicle should project events into it. The projection
  definition lives right next to the struct fields — no separate projection
  module is needed.

  ## Quick Example

      defmodule MyApp.ReadModels.Account do
        use Chronicle.ReadModel

        defstruct account_id: nil, owner_name: nil, balance: 0, transaction_count: 0

        from MyApp.Events.AccountOpened,
          set: [
            account_id: :event_source_id,
            owner_name: :owner_name,
            balance: :initial_balance
          ]

        from MyApp.Events.FundsDeposited,
          add: [balance: :amount, transaction_count: 1]

        from MyApp.Events.FundsWithdrawn,
          subtract: [balance: :amount],
          add: [transaction_count: 1]
      end

  ## Projection Macros

  ### `from/2`

  Maps properties from an event onto the read model.

      from MyApp.Events.AccountOpened,
        set: [account_id: :event_source_id, owner_name: :owner_name],
        count: :transaction_count

  Options:
    * `:key` — key expression identifying the model instance.
      Defaults to `"$eventSourceId"` when omitted.
    * `:parent_key` — parent key for nested models
    * `:set` — keyword list of `field: expression` pairs to set directly
    * `:add` — keyword list of `field: expression` pairs to add to
    * `:subtract` — keyword list of `field: expression` pairs to subtract from
    * `:count` — field atom to increment by 1 on each event occurrence

  ### `join/2`

  Joins a secondary event onto the model by a matching field.

      join MyApp.Events.AccountVerified,
        on: "accountId",
        set: [verified: true]

  Options:
    * `:on` — **(required)** the field name in the event to join on
    * `:key` — key expression (defaults to `"$eventSourceId"`)
    * `:set`, `:add`, `:subtract` — property mappings

  ### `removed_with/2`

  Removes the model instance when the given event occurs.

      removed_with MyApp.Events.AccountClosed,
        []

  Options:
    * `:key` — key expression (defaults to `"$eventSourceId"`)
    * `:parent_key` — parent key for nested models

  ### `from_every/1`

  Applies property mappings on every event, regardless of type.

      from_every set: [last_activity: "Occurred"]

  Options:
    * `:set`, `:add`, `:subtract` — property mappings applied to every event

  ## Property Expressions

  Values in `set:`, `add:`, and `subtract:` lists can be atoms, strings, or
  literals:

  - Use atoms for event fields (preferred): `:owner_name`, `:amount`
  - Use `:event_source_id` and `:occurred` for built-in context values
  - Use strings for advanced Chronicle expressions when needed
  - Use numbers and booleans as literal values

  | Expression | Meaning |
  |-----------|---------|
  | `:owner_name` | The `owner_name` field from the event |
  | `:event_source_id` | The event source identifier |
  | `:occurred` | When the event was recorded |
  | `1` | A literal integer constant |
  | `"$add(amount, balance)"` | An explicit Chronicle expression |

  ## Registering with Chronicle.Client

      {Chronicle.Client,
        ...
        read_models: [MyApp.ReadModels.Account]}

  ## Introspection

      MyApp.ReadModels.Account.__chronicle_read_model__(:id)
      MyApp.ReadModels.Account.__chronicle_read_model__(:from)
      MyApp.ReadModels.Account.__chronicle_read_model__(:join)
      MyApp.ReadModels.Account.__chronicle_read_model__(:removed_with)
      MyApp.ReadModels.Account.__chronicle_read_model__(:from_every)
      MyApp.ReadModels.Account.__chronicle_read_model__(:has_projection?)
  """

  @doc false
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      Module.register_attribute(__MODULE__, :chronicle_projection_from, accumulate: true)
      Module.register_attribute(__MODULE__, :chronicle_projection_join, accumulate: true)
      Module.register_attribute(__MODULE__, :chronicle_projection_removed_with, accumulate: true)
      Module.register_attribute(__MODULE__, :chronicle_projection_from_every, accumulate: true)

      @chronicle_read_model_id Keyword.get(opts, :id, __MODULE__ |> Module.split() |> List.last())

      import Chronicle.ReadModel, only: [from: 2, join: 2, removed_with: 2, from_every: 1]

      @before_compile Chronicle.ReadModel
    end
  end

  @doc """
  Declares how an event maps onto this read model.

  See the `Chronicle.ReadModel` module documentation for full options.
  """
  defmacro from(event_module, opts) do
    quote do
      @chronicle_projection_from {unquote(event_module), unquote(opts)}
    end
  end

  @doc """
  Declares a join from a secondary event onto this read model.

  See the `Chronicle.ReadModel` module documentation for full options.
  """
  defmacro join(event_module, opts) do
    quote do
      @chronicle_projection_join {unquote(event_module), unquote(opts)}
    end
  end

  @doc """
  Declares that this model is removed when the given event occurs.

  See the `Chronicle.ReadModel` module documentation for full options.
  """
  defmacro removed_with(event_module, opts \\ []) do
    quote do
      @chronicle_projection_removed_with {unquote(event_module), unquote(opts)}
    end
  end

  @doc """
  Applies property mappings on every event, regardless of type.

  See the `Chronicle.ReadModel` module documentation for full options.
  """
  defmacro from_every(opts) do
    quote do
      @chronicle_projection_from_every unquote(opts)
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      @doc false
      def __chronicle_read_model__(:id), do: @chronicle_read_model_id

      def __chronicle_read_model__(:from),
        do: @chronicle_projection_from |> Enum.reverse()

      def __chronicle_read_model__(:join),
        do: @chronicle_projection_join |> Enum.reverse()

      def __chronicle_read_model__(:removed_with),
        do: @chronicle_projection_removed_with |> Enum.reverse()

      def __chronicle_read_model__(:from_every),
        do: @chronicle_projection_from_every

      def __chronicle_read_model__(:has_projection?),
        do: not Enum.empty?(@chronicle_projection_from)
    end
  end
end
