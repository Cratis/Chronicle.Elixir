# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.ReadModels.ReadModel do
  @moduledoc """
  Macro for defining Chronicle read models with embedded model-bound projections.

  Use `Chronicle.ReadModels.ReadModel` in a struct module to define both the read model
  shape and how Chronicle should project events into it. The projection
  definition lives right next to the struct fields — no separate projection
  module is needed.

  ## Quick Example

      defmodule MyApp.ReadModels.Account do
        use Chronicle.ReadModels.ReadModel

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
      MyApp.ReadModels.Account.__chronicle_read_model__(:passive?)

  ## Passive Read Models

  Pass `passive: true` to mark a read model as passive. A passive projection does not
  actively observe events and never writes to a materialized sink — its instances are
  resolved on demand via immediate projection when looked up by id. This is useful for
  read models that only need to be queried by key (for example, from within a reactor).

      defmodule MyApp.ReadModels.Application do
        use Chronicle.ReadModels.ReadModel, passive: true

        defstruct id: nil, name: nil

        from MyApp.Events.ApplicationCreated,
          set: [id: :event_source_id, name: :name]
      end
  """

  @doc false
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      Module.register_attribute(__MODULE__, :chronicle_projection_from, accumulate: true)
      Module.register_attribute(__MODULE__, :chronicle_projection_join, accumulate: true)
      Module.register_attribute(__MODULE__, :chronicle_projection_removed_with, accumulate: true)
      Module.register_attribute(__MODULE__, :chronicle_projection_from_every, accumulate: true)
      Module.register_attribute(__MODULE__, :chronicle_projection_no_auto_map, accumulate: true)
      Module.register_attribute(__MODULE__, :chronicle_pii, accumulate: true)
      Module.register_attribute(__MODULE__, :chronicle_subject, [])

      @chronicle_read_model_id Keyword.get(opts, :id, __MODULE__ |> Module.split() |> List.last())
      @chronicle_read_model_passive Keyword.get(opts, :passive, false)
      @chronicle_read_model_rewindable not Keyword.get(opts, :not_rewindable, false)
      @chronicle_read_model_event_sequence Keyword.get(opts, :event_sequence, "event-log")

      import Chronicle.ReadModels.ReadModel,
        only: [
          from: 1,
          from: 2,
          join: 2,
          removed_with: 2,
          from_every: 1,
          no_auto_map: 0,
          no_auto_map: 1
        ]

      import Chronicle.Compliance, only: [pii: 1, pii: 2, subject: 1]

      @before_compile Chronicle.ReadModels.ReadModel
    end
  end

  @doc """
  Declares how an event maps onto this read model.

  See the `Chronicle.ReadModels.ReadModel` module documentation for full options.
  """
  defmacro from(event_module, opts \\ []) do
    quote do
      @chronicle_projection_from {unquote(event_module), unquote(opts)}
    end
  end

  @doc """
  Declares a join from a secondary event onto this read model.

  See the `Chronicle.ReadModels.ReadModel` module documentation for full options.
  """
  defmacro join(event_module, opts) do
    quote do
      @chronicle_projection_join {unquote(event_module), unquote(opts)}
    end
  end

  @doc """
  Declares that this model is removed when the given event occurs.

  See the `Chronicle.ReadModels.ReadModel` module documentation for full options.
  """
  defmacro removed_with(event_module, opts \\ []) do
    quote do
      @chronicle_projection_removed_with {unquote(event_module), unquote(opts)}
    end
  end

  @doc """
  Applies property mappings on every event, regardless of type.

  See the `Chronicle.ReadModels.ReadModel` module documentation for full options.
  """
  defmacro from_every(opts) do
    quote do
      @chronicle_projection_from_every unquote(opts)
    end
  end

  @doc """
  Disables Chronicle's automatic mapping of matching event property names onto this read model.

  Called with no arguments it turns AutoMap off for the whole projection, so every property has
  to be mapped explicitly. Called with a list of fields it leaves AutoMap on but excludes just
  those fields, which is what you want when a single property is set from something other than
  the event property that happens to share its name.

      no_auto_map()
      no_auto_map([:balance, :status])

  Without either, AutoMap is left at the kernel's default and cannot be turned off.
  """
  defmacro no_auto_map do
    quote do
      @chronicle_projection_no_auto_map :all
    end
  end

  @doc """
  Excludes specific fields from Chronicle's automatic property mapping.

  See `no_auto_map/0` for the whole-projection form.
  """
  defmacro no_auto_map(fields) do
    quote do
      @chronicle_projection_no_auto_map unquote(fields)
    end
  end

  @doc """
  Resolves accumulated `no_auto_map` declarations into the AutoMap setting and the excluded fields.

  Returns `{:disabled, []}` when AutoMap is off for the whole projection, `{:enabled, fields}`
  when specific fields are excluded, and `{:inherit, []}` when nothing was declared - which
  leaves the kernel's own default in place, exactly as before this could be declared at all.
  """
  @spec resolve_no_auto_map([:all | [atom()]]) :: {:inherit | :enabled | :disabled, [atom()]}
  def resolve_no_auto_map([]), do: {:inherit, []}

  def resolve_no_auto_map(declarations) do
    if Enum.member?(declarations, :all) do
      {:disabled, []}
    else
      {:enabled, declarations |> Enum.reverse() |> List.flatten() |> Enum.uniq()}
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
        do: @chronicle_projection_from_every |> Enum.reverse()

      def __chronicle_read_model__(:has_projection?),
        do: not Enum.empty?(@chronicle_projection_from)

      def __chronicle_read_model__(:passive?), do: @chronicle_read_model_passive

      def __chronicle_read_model__(:rewindable?), do: @chronicle_read_model_rewindable

      def __chronicle_read_model__(:event_sequence), do: @chronicle_read_model_event_sequence

      def __chronicle_read_model__(:no_auto_map),
        do: Chronicle.ReadModels.ReadModel.resolve_no_auto_map(@chronicle_projection_no_auto_map)

      def __chronicle_read_model__(:pii), do: Enum.reverse(@chronicle_pii)

      def __chronicle_read_model__(:subject), do: @chronicle_subject

      @doc false
      def __chronicle_pii__, do: Enum.reverse(@chronicle_pii)
    end
  end
end
