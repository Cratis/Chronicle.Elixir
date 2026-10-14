# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Projections.Projection do
  alias Chronicle.Projections.Validation

  @moduledoc """
  Macro for defining Chronicle declarative projections.

  A declarative projection is a standalone module that defines how events map onto
  a read model. Unlike model-bound projections — where `from` declarations live
  directly inside the read model module — a declarative projection keeps the read
  model as a pure data structure while the projection logic lives in a separate module.

  ## Quick Example

      defmodule MyApp.Projections.AccountSummaryProjection do
        use Chronicle.Projections.Projection, model: MyApp.ReadModels.AccountSummary

        from MyApp.Events.AccountOpened,
          set: [
            account_id: :event_source_id,
            owner_name: :owner_name,
            balance: :initial_balance
          ]

        from MyApp.Events.FundsDeposited,
          add: [balance: :amount]

        from MyApp.Events.FundsWithdrawn,
          subtract: [balance: :amount]
      end

  The read model (`AccountSummary`) is a plain struct using `use Chronicle.ReadModels.ReadModel`
  with no `from` declarations — it is a pure data shape, not a projection definition.

  ## Options

    * `:model` — **(required)** the read model module this projection writes into.
    * `:id` — identifier string for this projection. Defaults to the last segment
      of the module name (e.g. `"AccountSummaryProjection"`). A defaulted id (pin it
      explicitly to silence this) emits a one-time warning when discovered — see
      `Chronicle.Discovery.DefaultedIdWarning`.
    * `:passive` — when `true`, the projection does not actively observe events and
      never writes to a materialized sink; its read model is resolved on demand via
      immediate projection when looked up by id. Defaults to `false`.

  ## Projection Macros

  The following macros are available and carry the same options as their counterparts
  in `Chronicle.ReadModels.ReadModel`:

  - `from/1`, `from/2` — maps properties from an event onto the read model.
  - `join/2` — joins a secondary event onto the model by a matching field.
  - `removed_with/1`, `removed_with/2` — removes the model instance when the given event occurs.
  - `removed_with_join/1`, `removed_with_join/2` — removes the model instance when a secondary
    event matches it by a property instead of by its own key.
  - `clear_with/2`, `clear_with/3` — sets a field back to no value; sugar for `from event, clear: [...]`.
  - `from_every/1` — applies property mappings on every event, regardless of type.
  - `variant_of/2` — declares this projection to be one of several mutually exclusive
    representations of the same logical entity. See `Chronicle.ReadModels.ReadModel`.
  - `enters_on/1`, `enters_on/2` — names the event(s) that may create or resurrect this variant.

  ## Registering with Chronicle.Client

      {Chronicle.Client,
        ...
        projections: [MyApp.Projections.AccountSummaryProjection]}

  Or use `otp_app:` auto-discovery — modules that export `__chronicle_projection__/1`
  are discovered automatically.

  ## Introspection

      MyApp.Projections.AccountSummaryProjection.__chronicle_projection__(:id)
      MyApp.Projections.AccountSummaryProjection.__chronicle_projection__(:id_source)
      MyApp.Projections.AccountSummaryProjection.__chronicle_projection__(:model)
      MyApp.Projections.AccountSummaryProjection.__chronicle_projection__(:from)
      MyApp.Projections.AccountSummaryProjection.__chronicle_projection__(:join)
      MyApp.Projections.AccountSummaryProjection.__chronicle_projection__(:removed_with)
      MyApp.Projections.AccountSummaryProjection.__chronicle_projection__(:from_every)
  """

  @doc false
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      Module.register_attribute(__MODULE__, :chronicle_projection_from, accumulate: true)
      Module.register_attribute(__MODULE__, :chronicle_projection_join, accumulate: true)
      Module.register_attribute(__MODULE__, :chronicle_projection_removed_with, accumulate: true)

      Module.register_attribute(__MODULE__, :chronicle_projection_removed_with_join,
        accumulate: true
      )

      Module.register_attribute(__MODULE__, :chronicle_projection_from_every, accumulate: true)
      Module.register_attribute(__MODULE__, :chronicle_projection_no_auto_map, accumulate: true)
      Module.register_attribute(__MODULE__, :chronicle_projection_children, accumulate: true)
      Module.register_attribute(__MODULE__, :chronicle_enters_on, accumulate: true)
      Module.register_attribute(__MODULE__, :chronicle_variant_identity, [])
      Module.register_attribute(__MODULE__, :chronicle_variant_key, [])

      @chronicle_projection_model Keyword.fetch!(opts, :model)
      @chronicle_projection_id Keyword.get(opts, :id, __MODULE__ |> Module.split() |> List.last())
      @chronicle_projection_id_source if Keyword.has_key?(opts, :id),
                                        do: :explicit,
                                        else: :module_name
      @chronicle_projection_passive Keyword.get(opts, :passive, false)
      @chronicle_projection_rewindable not Keyword.get(opts, :not_rewindable, false)
      @chronicle_projection_event_sequence Keyword.get(opts, :event_sequence, "event-log")
      @chronicle_variant_identity nil
      @chronicle_variant_key nil

      import Chronicle.Projections.Projection,
        only: [
          from: 1,
          from: 2,
          join: 2,
          removed_with: 2,
          removed_with_join: 1,
          removed_with_join: 2,
          clear_with: 2,
          clear_with: 3,
          from_every: 1,
          variant_of: 2,
          enters_on: 1,
          enters_on: 2
        ]

      import Chronicle.ReadModels.ReadModel, only: [no_auto_map: 0, no_auto_map: 1]
      import Chronicle.Projections.Children, only: [children: 2, children: 3]

      @before_compile Chronicle.Projections.Projection
    end
  end

  @doc """
  Declares how an event maps onto the read model.

  See `Chronicle.ReadModels.ReadModel` for full options documentation.
  """
  defmacro from(event_module, opts \\ []) do
    Validation.reject_duplicate_properties!(
      Macro.to_string(event_module),
      opts,
      __CALLER__.module,
      __CALLER__
    )

    quote do
      @chronicle_projection_from {unquote(event_module), unquote(opts)}
    end
  end

  @doc """
  Declares a join from a secondary event onto the read model.

  See `Chronicle.ReadModels.ReadModel` for full options documentation.
  """
  defmacro join(event_module, opts) do
    Validation.require_on!(Macro.to_string(event_module), opts, __CALLER__.module, __CALLER__)

    Validation.reject_duplicate_properties!(
      Macro.to_string(event_module),
      opts,
      __CALLER__.module,
      __CALLER__
    )

    quote do
      @chronicle_projection_join {unquote(event_module), unquote(opts)}
    end
  end

  @doc """
  Declares that the read model instance is removed when the given event occurs.

  See `Chronicle.ReadModels.ReadModel` for full options documentation.
  """
  defmacro removed_with(event_module, opts \\ []) do
    quote do
      @chronicle_projection_removed_with {unquote(event_module), unquote(opts)}
    end
  end

  @doc """
  Declares that the read model instance is removed when a secondary event matches it by a
  property, instead of by its own key.

  See `Chronicle.ReadModels.ReadModel` for full options documentation.
  """
  defmacro removed_with_join(event_module, opts \\ []) do
    quote do
      @chronicle_projection_removed_with_join {unquote(event_module), unquote(opts)}
    end
  end

  @doc """
  Sets a field back to no value when the given event occurs. Sugar for `from event, clear: [...]`.

  See `Chronicle.ReadModels.ReadModel` for full options documentation.
  """
  defmacro clear_with(event_module, fields, opts \\ []) do
    merged = Keyword.put(opts, :clear, fields)

    Validation.reject_duplicate_properties!(
      Macro.to_string(event_module),
      merged,
      __CALLER__.module,
      __CALLER__
    )

    quote do
      @chronicle_projection_from {unquote(event_module), unquote(merged)}
    end
  end

  @doc """
  Applies property mappings on every event, regardless of type.

  Supports dictionary fields keyed by event context values:

      from_every increment: [event_counts: {:event_context, :type}]

  See `Chronicle.ReadModels.ReadModel` for full options documentation.
  """
  defmacro from_every(opts) do
    Validation.reject_duplicate_properties!("from_every", opts, __CALLER__.module, __CALLER__)

    quote do
      @chronicle_projection_from_every unquote(opts)
    end
  end

  @doc """
  Declares this projection to be one of several mutually exclusive representations of the same
  logical entity. See `Chronicle.ReadModels.ReadModel.variant_of/2` for full documentation.
  """
  defmacro variant_of(identity_module, opts) do
    quote do
      @chronicle_variant_identity unquote(identity_module)
      @chronicle_variant_key unquote(Keyword.fetch!(opts, :key))
    end
  end

  @doc """
  Names an event that may create or resurrect this projection's variant. See
  `Chronicle.ReadModels.ReadModel.enters_on/2` for full documentation.
  """
  defmacro enters_on(event_module, opts \\ []) do
    quote do
      @chronicle_enters_on {unquote(event_module), unquote(opts)}
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      @doc false
      def __chronicle_projection__(:id), do: @chronicle_projection_id

      @doc false
      def __chronicle_projection__(:id_source), do: @chronicle_projection_id_source

      @doc false
      def __chronicle_projection__(:model), do: @chronicle_projection_model

      @doc false
      def __chronicle_projection__(:passive?), do: @chronicle_projection_passive

      def __chronicle_projection__(:rewindable?), do: @chronicle_projection_rewindable

      def __chronicle_projection__(:event_sequence), do: @chronicle_projection_event_sequence

      def __chronicle_projection__(:no_auto_map),
        do: Chronicle.ReadModels.ReadModel.resolve_no_auto_map(@chronicle_projection_no_auto_map)

      def __chronicle_projection__(:from),
        do: @chronicle_projection_from |> Enum.reverse()

      def __chronicle_projection__(:join),
        do: @chronicle_projection_join |> Enum.reverse()

      def __chronicle_projection__(:removed_with),
        do: @chronicle_projection_removed_with |> Enum.reverse()

      def __chronicle_projection__(:removed_with_join),
        do: @chronicle_projection_removed_with_join |> Enum.reverse()

      def __chronicle_projection__(:children),
        do: @chronicle_projection_children |> Enum.reverse()

      def __chronicle_projection__(:from_every),
        do: @chronicle_projection_from_every

      def __chronicle_projection__(:variant_identity), do: @chronicle_variant_identity

      def __chronicle_projection__(:variant_key), do: @chronicle_variant_key

      def __chronicle_projection__(:enters_on), do: @chronicle_enters_on |> Enum.reverse()
    end
  end
end
