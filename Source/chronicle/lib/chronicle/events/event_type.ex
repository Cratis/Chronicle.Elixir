# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Events.EventType do
  @moduledoc """
  Macro for defining Chronicle event types.

  Use `Chronicle.Events.EventType` in an event struct module to annotate it with a
  stable event type identifier and generation number. Chronicle uses these to
  register the event schema and route events to the correct observers.

  You can also declare model-bound constraints directly on the event type
  through attributes:

      defmodule MyApp.Events.UserRegistered do
        use Chronicle.Events.EventType, id: "user-registered-v1"
        defstruct [:email]

        @unique :email
        unique_event_type()
      end

      defmodule MyApp.Events.UserDeleted do
        use Chronicle.Events.EventType, id: "user-deleted-v1"
        defstruct [:email]

        @remove_constraint "email"
      end

  ## Usage

      defmodule MyApp.Events.AccountOpened do
        use Chronicle.Events.EventType, id: "account-opened-v1"
        defstruct account_id: "", owner_name: "", initial_balance: 0
      end

  With an explicit generation:

      defmodule MyApp.Events.FundsDeposited do
        use Chronicle.Events.EventType, id: "funds-deposited", generation: 2
        defstruct account_id: "", amount: 0, currency: ""
      end

  ## Introspection

  Modules that `use Chronicle.Events.EventType` expose metadata via
  `__chronicle_event_type__/1`:

      MyApp.Events.AccountOpened.__chronicle_event_type__(:id)
      #=> "account-opened-v1"

      MyApp.Events.AccountOpened.__chronicle_event_type__(:generation)
      #=> 1

  ## Options

    * `:id` — the stable event type identifier (required, unless `:generation_for` is given)
    * `:generation` — the generation number (default `1`; required when `:generation_for` is
      given)
    * `:generation_for` — marks this module as a **previous generation** of the event type
      module it names, instead of giving it its own `:id`. The event type id is resolved from
      the target module, so the two generations can never drift apart by a hand-typed,
      mismatched id string. Cannot be combined with `:id`; the target module must itself `use
      Chronicle.Events.EventType`.

          defmodule MyApp.Events.AccountOpenedV1 do
            use Chronicle.Events.EventType, generation_for: MyApp.Events.AccountOpened, generation: 1
            defstruct account_id: "", owner_name: ""
          end
    * `:subject` — the field holding the event's data subject, the person whose PII the event
      carries (`subject: :customer_id`). It is resolved on append unless an explicit `:subject`
      option is given, and decides whose erasure key protects the event's PII. Without it the
      kernel falls back to the event source id.
    * `:tags` — tags every append of this event type carries, merged with per-append `:tags`
    * `:tombstone` — marks the event type as a tombstone (the last event of an event source's life)
      (mirrors .NET's `[Tombstone]`)
    * `:public` — makes the event type visible to other event stores, e.g. through event store
      subscriptions (mirrors `[Public]`)
    * `:compensation_for` — the event type module this event compensates for
      (mirrors `[CompensationFor<T>]`)
    * `:types` — type hints for nested fields; see `Chronicle.Serialization`

  When you append an event, the client encodes its fields as camelCase JSON:
  `owner_name` is stored as `ownerName`. Give every field a typed default, such
  as `initial_balance: 0`; the JSON schema Chronicle validates appends against is
  generated from the defaults, and a `nil` default registers the field as a
  string.
  """

  @doc """
  Resolves the data subject of an event from its declared `:subject` field, if it has one.

  An event type declares the field holding the subject (the person whose PII it carries)
  with `use Chronicle.Events.EventType, id: "...", subject: :customer_id`. A `Chronicle.Concept`
  value is unwrapped. Returns `nil` when no subject is declared or the field is empty.
  """
  @spec declared_subject(struct()) :: String.t() | nil
  def declared_subject(%module{} = event) do
    with true <- function_exported?(module, :__chronicle_event_type__, 1),
         field when not is_nil(field) <- module.__chronicle_event_type__(:subject) do
      case Map.get(event, field) do
        %{value: value} when not is_nil(value) -> to_string(value)
        value when is_binary(value) and value != "" -> value
        value when is_integer(value) -> Integer.to_string(value)
        _ -> nil
      end
    else
      _ -> nil
    end
  end

  def declared_subject(_), do: nil

  @doc """
  The tags every append of this event type carries (declared with `tags:`).
  """
  @spec declared_tags(struct()) :: [String.t()]
  def declared_tags(%module{}) do
    if function_exported?(module, :__chronicle_event_type__, 1),
      do: module.__chronicle_event_type__(:tags) |> List.wrap() |> Enum.map(&to_string/1),
      else: []
  end

  def declared_tags(_), do: []

  @doc """
  Returns whether `module` is a Chronicle event type (`use Chronicle.Events.EventType`).

  Every append path checks this before building a request, so an event struct that never
  registered an event type fails with a structured `{:error, {:unknown_event_type, module}}`
  instead of raising deep inside request building.
  """
  @spec event_type?(module()) :: boolean()
  def event_type?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :__chronicle_event_type__, 1)
  end

  def event_type?(_), do: false

  @doc """
  Returns metadata for this event type module.

  Accepts `:id`, `:generation`, or `:constraints` as the key.
  """
  @callback __chronicle_event_type__(
              key ::
                :id
                | :generation
                | :generation_for
                | :constraints
                | :pii
                | :encrypted
                | :subject
                | :tags
                | :tombstone
                | :public
                | :compensation_for
            ) :: term()

  defmacro __using__(opts) do
    generation_for = Keyword.get(opts, :generation_for)
    explicit_id = Keyword.get(opts, :id)

    if generation_for && explicit_id do
      raise Chronicle.Events.EventTypeGenerationForCannotBeCombinedWithEventType,
        module: __CALLER__.module
    end

    if generation_for && !Keyword.has_key?(opts, :generation) do
      raise ArgumentError,
            "#{inspect(__CALLER__.module)}: generation_for: requires an explicit :generation " <>
              "(the generation this module represents)"
    end

    unless generation_for || explicit_id do
      # Preserve the original KeyError shape for the plain, non-generation_for case.
      Keyword.fetch!(opts, :id)
    end

    generation = Keyword.get(opts, :generation, 1)
    field_types = Keyword.get(opts, :types, [])
    subject = Keyword.get(opts, :subject)
    tags = Keyword.get(opts, :tags, [])
    tombstone = Keyword.get(opts, :tombstone, false)
    public = Keyword.get(opts, :public, false)
    compensation_for = Keyword.get(opts, :compensation_for)

    quote do
      @behaviour Chronicle.Events.EventType

      Module.register_attribute(__MODULE__, :unique, accumulate: true)
      Module.register_attribute(__MODULE__, :remove_constraint, accumulate: true)
      Module.register_attribute(__MODULE__, :unique_event_type, accumulate: true)
      Module.register_attribute(__MODULE__, :closes_stream, accumulate: true)
      Module.register_attribute(__MODULE__, :chronicle_pii, accumulate: true)
      Module.register_attribute(__MODULE__, :chronicle_encrypted, accumulate: true)

      import Chronicle.Events.EventType,
        only: [
          unique: 1,
          unique: 2,
          unique_event_type: 0,
          unique_event_type: 1,
          remove_constraint: 1,
          remove_constraint: 2,
          closes_stream: 0,
          closes_stream: 1
        ]

      import Chronicle.Compliance, only: [pii: 1, pii: 2]
      import Chronicle.Confidentiality, only: [encrypted: 1, encrypted: 2, encrypted: 3]

      @chronicle_event_type_explicit_id unquote(explicit_id)
      @chronicle_event_type_generation_for unquote(generation_for)
      @chronicle_event_type_generation unquote(generation)
      @chronicle_field_types unquote(field_types)
      @chronicle_event_subject unquote(subject)
      @chronicle_event_tags unquote(tags)
      @chronicle_event_tombstone unquote(tombstone)
      @chronicle_event_public unquote(public)
      @chronicle_event_compensation_for unquote(compensation_for)

      @before_compile Chronicle.Events.EventType
    end
  end

  @doc false
  # Generates the `__chronicle_event_type__/1` accessors after the module body
  # has been fully expanded. This is essential for the `:constraints` accessor:
  # the `@unique`, `@unique_event_type`, and `@remove_constraint` attributes are
  # accumulated by the `unique/1,2`, `unique_event_type/0,1`, and
  # `remove_constraint/1` macros that appear *after* `use Chronicle.Events.EventType`.
  # Reading them at `@before_compile` time captures their final values; reading
  # them inline in `__using__` would always see empty lists.
  defmacro __before_compile__(_env) do
    quote do
      @chronicle_event_type_id (case @chronicle_event_type_generation_for do
                                  nil ->
                                    @chronicle_event_type_explicit_id

                                  target_module ->
                                    Code.ensure_compiled!(target_module)

                                    unless function_exported?(
                                             target_module,
                                             :__chronicle_event_type__,
                                             1
                                           ) do
                                      raise Chronicle.Events.EventTypeGenerationReferencesNonEventType,
                                        module: __MODULE__,
                                        referenced_module: target_module
                                    end

                                    target_module.__chronicle_event_type__(:id)
                                end)

      @impl Chronicle.Events.EventType
      def __chronicle_event_type__(:id), do: @chronicle_event_type_id
      def __chronicle_event_type__(:generation), do: @chronicle_event_type_generation
      def __chronicle_event_type__(:generation_for), do: @chronicle_event_type_generation_for

      def __chronicle_event_type__(:constraints) do
        constraints = %{
          unique: Enum.reverse(@unique),
          unique_event_type: Enum.reverse(@unique_event_type),
          remove_constraint: Enum.reverse(@remove_constraint)
        }

        # Only present when declared, so event types without a closing event keep their shape.
        if @closes_stream == [],
          do: constraints,
          else: Map.put(constraints, :closes_stream, Enum.reverse(@closes_stream))
      end

      @doc false
      def __chronicle_field_types__, do: @chronicle_field_types

      def __chronicle_event_type__(:subject), do: @chronicle_event_subject
      def __chronicle_event_type__(:tags), do: @chronicle_event_tags
      def __chronicle_event_type__(:tombstone), do: @chronicle_event_tombstone
      def __chronicle_event_type__(:public), do: @chronicle_event_public
      def __chronicle_event_type__(:compensation_for), do: @chronicle_event_compensation_for

      def __chronicle_event_type__(:pii), do: Enum.reverse(@chronicle_pii)
      def __chronicle_event_type__(:encrypted), do: Enum.reverse(@chronicle_encrypted)

      @doc false
      def __chronicle_pii__, do: Enum.reverse(@chronicle_pii)

      @doc false
      def __chronicle_encrypted__, do: Enum.reverse(@chronicle_encrypted)
    end
  end

  @doc """
  Declares a unique constraint for one or more event fields.

  This is equivalent to setting `@unique`. Supported `opts`:

    * `:name` — explicit constraint name (defaults to the first field name)
    * `:mode` — `:per_event_source` (default) keeps one value per event source and releases the
      previous value when it is replaced; `:per_value` keeps every value until a removal event
      (`remove_constraint/1`) releases it
    * `:ignore_casing` — compare values case-insensitively
    * `:message` — human-readable message to use when the constraint is
      violated
    * `:scope` — narrows uniqueness checking to values observed at append
      time along one or more dimensions, mirroring the C# client's
      `IConstraintBuilder.PerEventSourceType()`/`PerEventStreamType()`/
      `PerEventStreamId()`. An atom (`:per_event_source_type`,
      `:per_event_stream_type`, or `:per_event_stream_id`) or a list of them.
      Defaults to unscoped (globally unique across the whole event store).
    * `:event_sequences` — restrict the declaration to specific event
      sequences (default: all)

  `:message` also accepts a `{Module, :function}` callback invoked with the violation to
  compute one; see `Chronicle.Events.ConstraintViolation.details/1`.

  An unknown option, an invalid `:mode`, or an invalid `:scope` value emits a compile warning
  (the declaration still compiles; an unknown `:mode` then raises `ArgumentError` when the
  constraint definition is built, as in earlier releases).

  ## Scoping example

      # Unique only within events for the same event source type — the same
      # value may repeat across different event source types.
      unique(:email, scope: :per_event_source_type)
  """
  defmacro unique(fields, opts \\ []) do
    validate_unique_opts!(
      __CALLER__,
      opts,
      [:name, :mode, :ignore_casing, :message, :scope, :event_sequences],
      "unique/2"
    )

    quote do
      @unique {unquote(fields), unquote(opts)}
    end
  end

  @doc """
  Declares a unique constraint for the whole event type.

  This is equivalent to setting `@unique_event_type`. Supported `opts`:

    * `:name` — explicit constraint name (defaults to the event type id)
    * `:message` — human-readable message to use when the constraint is
      violated, or a `{Module, :function}` callback; see `unique/2`
    * `:scope` — see `unique/2`
    * `:event_sequences` — see `unique/2`

  An unknown option or an invalid `:scope` value emits a compile warning.
  """
  defmacro unique_event_type(opts \\ []) do
    validate_unique_opts!(
      __CALLER__,
      opts,
      [:name, :message, :scope, :event_sequences],
      "unique_event_type/1"
    )

    quote do
      @unique_event_type unquote(opts)
    end
  end

  @doc false
  # Option problems are compile warnings, not errors: the options were silently
  # accepted by earlier releases, so a module that compiled then must still compile.
  # `opts` is macro AST: when it is not a literal keyword list (for example a module
  # attribute) nothing can be checked at compile time, and a `:mode`/`:scope` value that
  # is not a literal is skipped for the same reason.
  def validate_unique_opts!(caller, opts, allowed_keys, context) do
    if Keyword.keyword?(opts) do
      literal = Enum.filter(opts, &literal_option?/1)

      case Chronicle.Events.Constraints.validate_unique_opts(literal, allowed_keys) do
        :ok ->
          :ok

        {:error, reason} ->
          IO.warn(
            "#{inspect(caller.module)}: #{context} #{reason}",
            Macro.Env.stacktrace(caller)
          )
      end
    else
      :ok
    end
  end

  defp literal_option?({:mode, value}), do: is_atom(value)
  defp literal_option?({:scope, value}) when is_atom(value), do: true
  defp literal_option?({:scope, value}) when is_list(value), do: Enum.all?(value, &is_atom/1)
  defp literal_option?({:scope, _}), do: false
  defp literal_option?(_), do: true

  @doc """
  Declares that appending this event **closes a stream scope** (a *closing event*).

  The kernel writes the event and the closure together; every later event inside the closed
  scope is refused with a stream-closed violation, while events elsewhere are unaffected. Use it
  when a domain fact ends something: a delivered report, closed books, a superseded version.
  Mirrors .NET's `[ClosesStream]`. Supported `opts`:

    * `:dimensions` - the participating dimensions, a list of `:event_source_id`,
      `:event_source_type`, `:event_stream_type` and `:event_stream_id`. Defaults to
      `[:event_source_id, :event_stream_type, :event_stream_id]`.
    * `:event_stream_id_from` - the event field supplying the stream id instead of the append
      (implies the `:event_stream_id` dimension)
    * `:reopened_by` - event type modules that lift the closure of exactly this scope
    * `:name` - the owning constraint name (defaults to the event type id); declarations that
      share a name merge, and must use the same dimensions and stream id field
    * `:event_sequences` - restrict the declaration to specific event sequences (default: all)

  Registering a declaration closes nothing in history; only later appends close scopes.

      defmodule MyApp.Events.PeriodClosed do
        use Chronicle.Events.EventType, id: "period-closed"
        defstruct period: ""

        closes_stream event_stream_id_from: :period, reopened_by: [MyApp.Events.PeriodReopened]
      end
  """
  defmacro closes_stream(opts \\ []) do
    quote do
      @closes_stream unquote(opts)
    end
  end

  @doc """
  Declares that appending this event removes a named constraint.

  This is equivalent to setting `@remove_constraint`.
  """
  defmacro remove_constraint(name) do
    quote do
      @remove_constraint unquote(name)
    end
  end

  @doc """
  Declares that appending this event removes a named constraint, carrying the value to
  release.

  `:properties` names the constrained properties, in the same order as the `unique/2`
  declaration, that this event carries the value of (empty or omitted releases every value for
  the event source, same as `remove_constraint/1`). Only meaningful for a `:per_value` unique
  constraint — a unique event type constraint has no constrained value to carry.

      defmodule MyApp.Events.MappingVersionRemoved do
        use Chronicle.Events.EventType, id: "mapping-version-removed"
        defstruct [:version_id]

        remove_constraint("UniqueMappingVersionId", properties: [:version_id])
      end
  """
  defmacro remove_constraint(name, opts) do
    quote do
      @remove_constraint {unquote(name), unquote(opts)}
    end
  end
end
