# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Projections.Projection do
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
      of the module name (e.g. `"AccountSummaryProjection"`).

  ## Projection Macros

  The following macros are available and carry the same options as their counterparts
  in `Chronicle.ReadModels.ReadModel`:

  - `from/1`, `from/2` — maps properties from an event onto the read model.
  - `join/2` — joins a secondary event onto the model by a matching field.
  - `removed_with/1`, `removed_with/2` — removes the model instance when the given event occurs.
  - `from_every/1` — applies property mappings on every event, regardless of type.

  ## Registering with Chronicle.Client

      {Chronicle.Client,
        ...
        projections: [MyApp.Projections.AccountSummaryProjection]}

  Or use `otp_app:` auto-discovery — modules that export `__chronicle_projection__/1`
  are discovered automatically.

  ## Introspection

      MyApp.Projections.AccountSummaryProjection.__chronicle_projection__(:id)
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
      Module.register_attribute(__MODULE__, :chronicle_projection_from_every, accumulate: true)

      @chronicle_projection_model Keyword.fetch!(opts, :model)
      @chronicle_projection_id Keyword.get(opts, :id, __MODULE__ |> Module.split() |> List.last())

      import Chronicle.Projections.Projection,
        only: [from: 1, from: 2, join: 2, removed_with: 2, from_every: 1]

      @before_compile Chronicle.Projections.Projection
    end
  end

  @doc """
  Declares how an event maps onto the read model.

  See `Chronicle.ReadModels.ReadModel` for full options documentation.
  """
  defmacro from(event_module, opts \\ []) do
    quote do
      @chronicle_projection_from {unquote(event_module), unquote(opts)}
    end
  end

  @doc """
  Declares a join from a secondary event onto the read model.

  See `Chronicle.ReadModels.ReadModel` for full options documentation.
  """
  defmacro join(event_module, opts) do
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
  Applies property mappings on every event, regardless of type.

  See `Chronicle.ReadModels.ReadModel` for full options documentation.
  """
  defmacro from_every(opts) do
    quote do
      @chronicle_projection_from_every unquote(opts)
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      @doc false
      def __chronicle_projection__(:id), do: @chronicle_projection_id

      @doc false
      def __chronicle_projection__(:model), do: @chronicle_projection_model

      def __chronicle_projection__(:from),
        do: @chronicle_projection_from |> Enum.reverse()

      def __chronicle_projection__(:join),
        do: @chronicle_projection_join |> Enum.reverse()

      def __chronicle_projection__(:removed_with),
        do: @chronicle_projection_removed_with |> Enum.reverse()

      def __chronicle_projection__(:from_every),
        do: @chronicle_projection_from_every
    end
  end
end
