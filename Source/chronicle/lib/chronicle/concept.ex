# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Concept do
  @moduledoc """
  Macro for defining Chronicle concepts — strongly-typed wrappers over a
  single primitive value, mirroring `ConceptAs<T>` in the C# client and
  `ConceptAs` in the Kotlin client.

  A concept lets you declare a domain value's type — and, critically, its
  compliance classification — exactly once, on the type itself, instead of
  repeating a `pii/1,2` annotation on every event or read model field that
  happens to hold that value.

  ## Defining a concept

      defmodule MyApp.PersonName do
        use Chronicle.Concept, type: :string
        pii "Legal name of the data subject"
      end

  Any struct field across your event types and read models that defaults to
  `%MyApp.PersonName{}` is now automatically recognized by
  `Chronicle.Schemas.JsonSchemaGenerator` as carrying PII — see that module's
  documentation for how type-level compliance is resolved and pushed down
  onto schema leaves.

  ## Options for `use Chronicle.Concept`

    * `:type` — **(required)** the primitive type the concept wraps. One of
      `:string`, `:integer`, `:float`, `:boolean`, or `:uuid`. Any other
      value raises `ArgumentError` at compile time.
    * `:event_source_id` — when `true`, marks this concept as representing a
      Chronicle event source identifier, mirroring `EventSourceId<T>` in the
      C# client. Defaults to `false`. A concept declared with
      `event_source_id: true` cannot also declare `pii/0,1` — see
      "PII is not supported on an event source id" below.

  ## What `use Chronicle.Concept` generates

    * `defstruct value: <default>` — a single-field struct wrapping the
      declared type's sensible zero value (`""` for `:string` and `:uuid`,
      `0` for `:integer`, `0.0` for `:float`, `false` for `:boolean`).
    * `__chronicle_concept__/1` — introspection, accepting `:type`,
      `:event_source_id?`, or `:pii` as the key.
    * A `Jason.Encoder` implementation that serializes the concept as its
      **wrapped value**, not as an object wrapping one — `Jason.encode!(%MyApp.PersonName{value: "Ada"})`
      produces `"Ada"`, exactly as `Jason.encode!("Ada")` would. This is
      critical: it is what lets an existing property already in production
      be adopted into a concept without changing the wire format or the
      registered schema, mirroring the intent of Kotlin's
      `ConceptTypeAdapterFactory` and the KDoc on `io.cratis.chronicle.concepts.ConceptAs`.
    * `__chronicle_pii__/0` — present on every concept module (empty when no
      `pii/0,1` was declared), so `Chronicle.Schemas.JsonSchemaGenerator` can
      treat every concept module uniformly, the same way it already treats
      `Chronicle.Events.EventType` and `Chronicle.ReadModels.ReadModel` modules.

  ## Declaring PII on a concept

  Use `pii/0` or `pii/1` — **not** `Chronicle.Compliance.pii/1,2`, which
  expects a field name as its first argument. A concept has exactly one
  field (`:value`), so its `pii/0,1` takes only the optional `details` text:

      defmodule MyApp.NationalId do
        use Chronicle.Concept, type: :string
        pii "National ID number — sensitive personal identifier"
      end

  ## PII is not supported on an event source id

  Chronicle uses the event source id to look up the encryption key for a
  subject's PII values. A concept cannot be both the key used to find the
  encryption key *and* one of the values encrypted under it, so declaring
  `pii/0,1` on a concept created with `event_source_id: true` raises
  `ArgumentError` at compile time — mirroring the C# client's
  `PIINotSupportedOnEventSourceId`:

      defmodule MyApp.EmployeeId do
        use Chronicle.Concept, type: :uuid, event_source_id: true
        pii "this raises ArgumentError"
      end

  If the identifier itself is sensitive, use a non-sensitive surrogate
  (`event_source_id: true`, no `pii`) as the event source id, and store the
  sensitive value in a separate PII-marked concept or event property.

  ## Registering a value

  A concept is a plain struct — construct it like any other:

      %MyApp.PersonName{value: "Ada Lovelace"}
  """

  @valid_types [:string, :integer, :float, :boolean, :uuid]

  @doc """
  Returns metadata for this concept module.

  Accepts `:type`, `:event_source_id?`, or `:pii` as the key.
  """
  @callback __chronicle_concept__(key :: :type | :event_source_id? | :pii) :: term()

  defmacro __using__(opts) do
    type = fetch_type!(opts)
    default = default_value_for(type)
    event_source_id? = Keyword.get(opts, :event_source_id, false)

    quote do
      @behaviour Chronicle.Concept

      Module.register_attribute(__MODULE__, :chronicle_pii, accumulate: true)

      @chronicle_concept_type unquote(type)
      @chronicle_concept_event_source_id unquote(event_source_id?)

      defstruct value: unquote(default)

      import Chronicle.Concept, only: [pii: 0, pii: 1]

      @before_compile Chronicle.Concept
    end
  end

  @doc """
  Marks this concept's wrapped value as containing Personally Identifiable
  Information (PII).

  `details` is an optional human-readable explanation of why the value is
  classified as PII and defaults to an empty string. Cannot be combined with
  `event_source_id: true` — see the module documentation.
  """
  defmacro pii(details \\ "") do
    quote do
      @chronicle_pii {:value, unquote(details)}
    end
  end

  @doc false
  defmacro __before_compile__(_env) do
    quote do
      if @chronicle_concept_event_source_id and @chronicle_pii != [] do
        raise ArgumentError,
              "#{inspect(__MODULE__)} cannot declare pii/0,1: PII is not supported on a " <>
                "Chronicle.Concept declared with event_source_id: true. The event source id " <>
                "is used to look up the encryption key, so it cannot itself be an encrypted " <>
                "value. Use a non-sensitive surrogate as the event source id and store the " <>
                "sensitive value in a separate PII-marked concept or event property."
      end

      @impl Chronicle.Concept
      def __chronicle_concept__(:type), do: @chronicle_concept_type
      def __chronicle_concept__(:event_source_id?), do: @chronicle_concept_event_source_id
      def __chronicle_concept__(:pii), do: Enum.reverse(@chronicle_pii)

      @doc false
      def __chronicle_pii__, do: Enum.reverse(@chronicle_pii)

      defimpl Jason.Encoder, for: __MODULE__ do
        @moduledoc false

        @doc false
        def encode(%{value: value}, opts), do: Jason.Encoder.encode(value, opts)
      end
    end
  end

  defp fetch_type!(opts) do
    case Keyword.fetch(opts, :type) do
      {:ok, type} ->
        type

      :error ->
        raise ArgumentError,
              "Chronicle.Concept requires a :type option, e.g. `use Chronicle.Concept, type: :string`"
    end
  end

  defp default_value_for(:string), do: ""
  defp default_value_for(:integer), do: 0
  defp default_value_for(:float), do: 0.0
  defp default_value_for(:boolean), do: false
  defp default_value_for(:uuid), do: ""

  defp default_value_for(type) do
    raise ArgumentError,
          "unknown Chronicle.Concept type #{inspect(type)} — expected one of #{inspect(@valid_types)}"
  end
end
