# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Events.Migration do
  @moduledoc """
  Behaviour and macro for defining event type migrations.

  Event type migrations define how to upcast and downcast between different
  generations of the same event type. This enables schema evolution while
  maintaining backward compatibility with historical events.

  ## Defining a migration

  Use `Chronicle.Events.Migration` in a module and implement the `upcast/1`
  and `downcast/1` callbacks. These functions receive a migration builder
  that provides a fluent API for transforming event properties.

      defmodule MyApp.Migrations.AccountOpenedV2Migration do
        use Chronicle.Events.Migration,
          from: {MyApp.Events.AccountOpenedV1, generation: 1},
          to: {MyApp.Events.AccountOpened, generation: 2}

        alias Chronicle.Events.MigrationBuilder

        @impl true
        def upcast(builder) do
          builder
          |> MigrationBuilder.default_value(:account_tier, "standard")
          |> MigrationBuilder.rename_property(:owner_name, :full_name)
        end

        @impl true
        def downcast(builder) do
          builder
          |> MigrationBuilder.rename_property(:full_name, :owner_name)
        end
      end

  ## Required options

    * `:from` — a tuple `{EventTypeModule, generation: generation_number}`
      specifying the source event type and generation.
    * `:to` — a tuple `{EventTypeModule, generation: generation_number}`
      specifying the target event type and generation.

  The `from` and `to` event types must have the same event type ID, and the
  `to` generation must be exactly one higher than the `from` generation.

  ## Migration chain

  Multiple migrations can be chained to migrate across multiple generations.
  Chronicle automatically composes these migrations when replaying or
  projecting historical events.

  ## Registering with Chronicle.Client

  Migrations are automatically discovered when using the `:otp_app` option:

      {Chronicle.Client,
        ...
        otp_app: :my_app}

  Or register them explicitly:

      {Chronicle.Client,
        ...
        migrations: [MyApp.Migrations.AccountOpenedV2Migration]}
  """

  @doc """
  Defines the upcast transformation from an older generation to a newer one.

  Receives a `Chronicle.Events.MigrationBuilder` and must return it after
  applying property transformations.
  """
  @callback upcast(builder :: Chronicle.Events.MigrationBuilder.t()) ::
              Chronicle.Events.MigrationBuilder.t()

  @doc """
  Defines the downcast transformation from a newer generation to an older one.

  Receives a `Chronicle.Events.MigrationBuilder` and must return it after
  applying property transformations.
  """
  @callback downcast(builder :: Chronicle.Events.MigrationBuilder.t()) ::
              Chronicle.Events.MigrationBuilder.t()

  @doc """
  Returns metadata for this migration module.
  """
  @callback __chronicle_migration__(
              key ::
                :from_module | :from_generation | :to_module | :to_generation | :event_type_id
            ) :: term()

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @behaviour Chronicle.Events.Migration

      from_spec = Keyword.fetch!(opts, :from)
      to_spec = Keyword.fetch!(opts, :to)

      {from_module, from_opts} =
        case from_spec do
          {module, opts} when is_atom(module) and is_list(opts) -> {module, opts}
          module when is_atom(module) -> {module, []}
          _ -> raise ArgumentError, ":from must be {Module, generation: n} or Module"
        end

      {to_module, to_opts} =
        case to_spec do
          {module, opts} when is_atom(module) and is_list(opts) -> {module, opts}
          module when is_atom(module) -> {module, []}
          _ -> raise ArgumentError, ":to must be {Module, generation: n} or Module"
        end

      from_generation = Keyword.get(from_opts, :generation, 1)
      to_generation = Keyword.get(to_opts, :generation, from_generation + 1)

      @chronicle_migration_from_module from_module
      @chronicle_migration_from_generation from_generation
      @chronicle_migration_to_module to_module
      @chronicle_migration_to_generation to_generation

      @before_compile Chronicle.Events.Migration

      @doc false
      def __chronicle_migration__(:from_module), do: @chronicle_migration_from_module
      def __chronicle_migration__(:from_generation), do: @chronicle_migration_from_generation
      def __chronicle_migration__(:to_module), do: @chronicle_migration_to_module
      def __chronicle_migration__(:to_generation), do: @chronicle_migration_to_generation

      def __chronicle_migration__(:event_type_id),
        do: @chronicle_migration_to_module.__chronicle_event_type__(:id)
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      if @chronicle_migration_to_generation != @chronicle_migration_from_generation + 1 do
        raise Chronicle.Events.InvalidMigrationGenerationGap,
          from_module: @chronicle_migration_from_module,
          to_module: @chronicle_migration_to_module,
          from_generation: @chronicle_migration_from_generation,
          to_generation: @chronicle_migration_to_generation
      end

      unless function_exported?(@chronicle_migration_from_module, :__chronicle_event_type__, 1) do
        raise ArgumentError,
              "#{inspect(@chronicle_migration_from_module)} must use Chronicle.EventType"
      end

      unless function_exported?(@chronicle_migration_to_module, :__chronicle_event_type__, 1) do
        raise ArgumentError,
              "#{inspect(@chronicle_migration_to_module)} must use Chronicle.EventType"
      end

      from_id = @chronicle_migration_from_module.__chronicle_event_type__(:id)
      to_id = @chronicle_migration_to_module.__chronicle_event_type__(:id)

      if from_id != to_id do
        raise ArgumentError,
              "Migration from and to event types must have the same ID. " <>
                "Got from=#{inspect(from_id)}, to=#{inspect(to_id)}"
      end
    end
  end
end
