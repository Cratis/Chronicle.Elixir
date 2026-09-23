# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Schemas.JsonSchemaGenerator do
  @moduledoc """
  Generates JSON schemas for struct-backed event types and read models.

  This is the single source of truth for schema generation shared by event type
  registration (`Chronicle.EventTypes`) and read model registration
  (`Chronicle.Registration.Coordinator`). Generating both through one path keeps
  property typing consistent and ensures compliance (PII) and security
  (Encrypted) metadata are always embedded the same way.

  PII and Encrypted are each resolved from two places, mirroring the C#
  client's `PIIMetadataProvider`/`EncryptedMetadataProvider`:

    * **Property-level** — a field marked with `Chronicle.Compliance.pii/1,2`
      or `Chronicle.Confidentiality.encrypted/1,2,3` on the event type or read
      model module itself.
    * **Type-level** — a field whose value is a `Chronicle.Concept` module
      that declared `pii/0,1` or `encrypted/0,1` on itself (see that module's
      documentation). The concept's classification travels with it
      automatically to every event and read model that uses it, without
      repeating the annotation at every call site.

  PII and Encrypted are deliberately separate mechanisms sharing only this
  generator: a field can carry one or the other, never both — see
  `Chronicle.Confidentiality.PiiAndEncryptedCombinedNotSupported`, raised
  here the moment both resolve for the same leaf.

  Nested structs (including concepts) are descended into recursively, and a
  `Chronicle.Concept` field is described by the schema of its **wrapped
  value**, not the wrapper struct — mirroring the concept's own
  `Jason.Encoder` implementation, so the schema always matches what actually
  goes on the wire.

  Compliance and security metadata are always written on schema **leaves**,
  never on a container (`"type" => "object"`) node: a marker left on a
  container would make Chronicle hand the whole JSON object to the handler
  and store one opaque ciphertext string where the schema still says
  `object`, so a released value comes back as a string instead of an object
  and the read model fails to materialize. An array is the one exception —
  metadata declared on the array *field itself* stays on the array (the
  collection is blob-encrypted as a whole); metadata resolved from the
  array's *element type* (a list of PII or Encrypted concepts) is attached to
  the `"items"` schema instead, which is already a leaf. A leaf reachable
  through more than one path (for example a PII concept nested inside a value
  object whose own field also carries a property-level `pii/1,2`) is only
  ever marked once.
  """

  alias Chronicle.Compliance.ComplianceMetadataType
  alias Chronicle.Confidentiality.PiiAndEncryptedCombinedNotSupported
  alias Chronicle.Confidentiality.SecurityMetadataType

  @opaque_struct_modules [DateTime, NaiveDateTime, Date, Time, MapSet, Range, URI, Regex, Version]

  @doc """
  Generates a JSON schema string for a struct module.

  ## Options

    * `:key_transform` — how struct field names are rendered as schema property
      names. `:camel` renders `snake_case` as `camelCase` (used for event types,
      whose content is serialized as camelCase); `:identity` keeps the field
      name as-is (used for read models, whose stored properties are snake_case).
      Defaults to `:identity`.

  PII fields are discovered through the module's `__chronicle_pii__/0` accessor
  when present, and recursively through the `__chronicle_pii__/0` of any field's
  value that is itself a struct (a `Chronicle.Concept`, or a plain nested value
  object holding one).
  """
  @spec generate(module(), keyword()) :: String.t()
  def generate(module, opts \\ []) do
    key_transform = Keyword.get(opts, :key_transform, :identity)
    properties = struct_properties(module, key_transform)

    check_no_conflicting_metadata!(properties)

    Jason.encode!(%{"type" => "object", "properties" => properties})
  end

  defp struct_properties(module, key_transform) do
    if function_exported?(module, :__struct__, 0) do
      pii = pii_for(module)
      encrypted = encrypted_for(module)

      module.__struct__()
      |> Map.from_struct()
      |> Enum.map(fn {key, default_value} ->
        schema =
          default_value
          |> property_schema(key_transform)
          |> maybe_add_compliance(Map.get(pii, key))
          |> maybe_add_security(Map.get(encrypted, key))

        {transform_key(key, key_transform), schema}
      end)
      |> Map.new()
    else
      %{}
    end
  end

  defp pii_for(module) do
    if function_exported?(module, :__chronicle_pii__, 0) do
      Map.new(module.__chronicle_pii__())
    else
      %{}
    end
  end

  defp encrypted_for(module) do
    if function_exported?(module, :__chronicle_encrypted__, 0) do
      module.__chronicle_encrypted__()
      |> Map.new(fn {field, scope, details} -> {field, {scope, details}} end)
    else
      %{}
    end
  end

  # Walks the fully-merged schema tree looking for a leaf that ended up with
  # both "compliance" and "security" populated. Checking the merged result,
  # rather than each resolution source individually, is what catches a
  # cross-source combination correctly - for example a property marked
  # pii/1,2 whose declared type is a concept marked encrypted/0,1: neither
  # the property's own markers nor the concept's own markers conflict with
  # themselves, only the union of what ends up on the leaf does. Mirrors the
  # C# client's EncryptedMetadataProvider.ThrowIfAlsoPII, checked at the same
  # point (schema generation), since this client has no compile-time
  # analyzer for it either.
  defp check_no_conflicting_metadata!(properties) when is_map(properties) do
    Enum.each(properties, fn {key, schema} -> check_no_conflicting_metadata!(schema, key) end)
  end

  # A container node never carries compliance/security metadata itself - both
  # are always pushed down onto leaves (see the moduledoc), so only the
  # nested properties need checking, never the container.
  defp check_no_conflicting_metadata!(%{"properties" => nested}, _key)
       when map_size(nested) > 0 do
    check_no_conflicting_metadata!(nested)
  end

  defp check_no_conflicting_metadata!(%{"items" => item_schema}, key) do
    check_no_conflicting_metadata!(item_schema, key)
  end

  defp check_no_conflicting_metadata!(schema, key), do: check_leaf!(schema, key)

  defp check_leaf!(schema, key) do
    if Map.get(schema, "compliance", []) != [] and Map.get(schema, "security", []) != [] do
      raise PiiAndEncryptedCombinedNotSupported, field: key
    end
  end

  # Use "number" without a format so the kernel converts JSON numbers via the
  # double path, which is the only one that works for JsonElement-backed numbers.
  defp property_schema(value, _key_transform) when is_integer(value), do: %{"type" => "number"}
  defp property_schema(value, _key_transform) when is_float(value), do: %{"type" => "number"}
  defp property_schema(value, _key_transform) when is_boolean(value), do: %{"type" => "boolean"}

  # A struct field is either a Chronicle.Concept (described by the schema of
  # its wrapped value, not the wrapper struct — the same rule its
  # Jason.Encoder follows for the wire format, with the concept's own
  # type-level PII travelling onto that leaf), a plain nested struct (a value
  # object that is not itself a concept, descended into field by field so PII
  # on a concept several levels deep is still found), or a struct Chronicle
  # does not own (DateTime and friends) — left as an opaque leaf, since
  # descending into its internal representation would produce a nonsensical
  # schema. `function_exported?/3` cannot appear in a guard, so the dispatch
  # happens in the function body instead of via multiple clauses.
  defp property_schema(%module{} = value, key_transform) do
    cond do
      function_exported?(module, :__chronicle_concept__, 1) ->
        value.value
        |> property_schema(key_transform)
        |> maybe_add_compliance(module |> pii_for() |> Map.get(:value))
        |> maybe_add_security(module |> encrypted_for() |> Map.get(:value))

      module in @opaque_struct_modules ->
        %{"type" => "string"}

      true ->
        %{"type" => "object", "properties" => struct_properties(module, key_transform, value)}
    end
  end

  # A non-empty list's element schema is inferred from its first element —
  # this generator works from struct field defaults rather than static types,
  # so a list field whose elements should carry compliance metadata (e.g. a
  # list of PII concepts) needs at least one representative element as its
  # default value. An empty default carries no type information to infer from.
  defp property_schema([first | _rest], key_transform) do
    %{"type" => "array", "items" => property_schema(first, key_transform)}
  end

  defp property_schema([], _key_transform),
    do: %{"type" => "array", "items" => %{"type" => "string"}}

  defp property_schema(_value, _key_transform), do: %{"type" => "string"}

  defp struct_properties(module, key_transform, value) do
    pii = pii_for(module)
    encrypted = encrypted_for(module)

    value
    |> Map.from_struct()
    |> Enum.map(fn {key, default_value} ->
      schema =
        default_value
        |> property_schema(key_transform)
        |> maybe_add_compliance(Map.get(pii, key))
        |> maybe_add_security(Map.get(encrypted, key))

      {transform_key(key, key_transform), schema}
    end)
    |> Map.new()
  end

  defp maybe_add_compliance(schema, nil), do: schema

  # Compliance metadata is pushed down onto every leaf of an object schema
  # rather than left on the container — see the moduledoc for why. An array
  # schema has no "properties" key, so it falls through to the leaf clause
  # below and keeps the marker on the array itself, which is the deliberate
  # exception documented there.
  defp maybe_add_compliance(%{"properties" => properties} = schema, details)
       when map_size(properties) > 0 do
    updated_properties =
      Map.new(properties, fn {key, prop_schema} ->
        {key, maybe_add_compliance(prop_schema, details)}
      end)

    %{schema | "properties" => updated_properties}
  end

  defp maybe_add_compliance(schema, details), do: add_compliance(schema, details)

  # A leaf can be reached by more than one PII-resolution path — for example a
  # concept's type-level pii/0,1 and a property-level pii/1,2 on the same
  # field. Recording the same metadata type twice adds nothing and makes the
  # generated schema noisier to read and to diff.
  defp add_compliance(schema, details) do
    metadata_type = ComplianceMetadataType.pii()
    existing = Map.get(schema, "compliance", [])

    if Enum.any?(existing, &(&1["metadataType"] == metadata_type)) do
      schema
    else
      Map.put(
        schema,
        "compliance",
        existing ++ [%{"metadataType" => metadata_type, "details" => details || ""}]
      )
    end
  end

  defp maybe_add_security(schema, nil), do: schema

  # Security metadata is pushed down onto every leaf of an object schema
  # exactly as compliance metadata is - see the moduledoc for why. Written
  # under its own "security" schema key, a sibling of "compliance" rather
  # than a shared one, so the kernel routes a value into exactly one
  # protection path.
  defp maybe_add_security(%{"properties" => properties} = schema, metadata)
       when map_size(properties) > 0 do
    updated_properties =
      Map.new(properties, fn {key, prop_schema} ->
        {key, maybe_add_security(prop_schema, metadata)}
      end)

    %{schema | "properties" => updated_properties}
  end

  defp maybe_add_security(schema, metadata), do: add_security(schema, metadata)

  # A leaf can be reached by more than one Encrypted-resolution path - for
  # example a concept's type-level encrypted/0,1 and a property-level
  # encrypted/1,2,3 on the same field. Recording the same metadata type twice
  # adds nothing and makes the generated schema noisier to read and to diff.
  defp add_security(schema, {scope, details}) do
    metadata_type = SecurityMetadataType.for_scope(scope)
    existing = Map.get(schema, "security", [])

    if Enum.any?(existing, &(&1["metadataType"] == metadata_type)) do
      schema
    else
      Map.put(
        schema,
        "security",
        existing ++ [%{"metadataType" => metadata_type, "details" => details || ""}]
      )
    end
  end

  defp transform_key(key, :identity), do: Atom.to_string(key)

  defp transform_key(key, :camel) do
    [head | tail] = key |> Atom.to_string() |> String.split("_")
    head <> Enum.map_join(tail, &String.capitalize/1)
  end
end
