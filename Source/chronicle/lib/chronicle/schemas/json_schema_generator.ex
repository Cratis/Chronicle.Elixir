# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Schemas.JsonSchemaGenerator do
  @moduledoc """
  Generates JSON schemas for struct-backed event types and read models.

  This is the single source of truth for schema generation shared by event type
  registration (`Chronicle.EventTypes`) and read model registration
  (`Chronicle.Registration.Coordinator`). Generating both through one path keeps
  property typing consistent and ensures compliance (PII) metadata is always
  embedded the same way.

  Fields marked with `Chronicle.Compliance.pii/1,2` are emitted with a
  `compliance` array on their property schema, which the Chronicle kernel reads
  to apply compliance-aware encryption.
  """

  alias Chronicle.Compliance.ComplianceMetadataType

  @doc """
  Generates a JSON schema string for a struct module.

  ## Options

    * `:key_transform` — how struct field names are rendered as schema property
      names. `:camel` renders `snake_case` as `camelCase` (used for event types,
      whose content is serialized as camelCase); `:identity` keeps the field
      name as-is (used for read models, whose stored properties are snake_case).
      Defaults to `:identity`.

  PII fields are discovered through the module's `__chronicle_pii__/0` accessor
  when present.
  """
  @spec generate(module(), keyword()) :: String.t()
  def generate(module, opts \\ []) do
    key_transform = Keyword.get(opts, :key_transform, :identity)
    pii = pii_for(module)

    properties =
      if function_exported?(module, :__struct__, 0) do
        module.__struct__()
        |> Map.from_struct()
        |> Enum.map(fn {key, default_value} ->
          schema = property_schema(default_value) |> maybe_add_compliance(Map.get(pii, key))
          {transform_key(key, key_transform), schema}
        end)
        |> Map.new()
      else
        %{}
      end

    Jason.encode!(%{"type" => "object", "properties" => properties})
  end

  defp pii_for(module) do
    if function_exported?(module, :__chronicle_pii__, 0) do
      Map.new(module.__chronicle_pii__())
    else
      %{}
    end
  end

  defp maybe_add_compliance(schema, nil), do: schema

  defp maybe_add_compliance(schema, details) do
    Map.put(schema, "compliance", [
      %{"metadataType" => ComplianceMetadataType.pii(), "details" => details || ""}
    ])
  end

  # Use "number" without a format so the kernel converts JSON numbers via the
  # double path, which is the only one that works for JsonElement-backed numbers.
  defp property_schema(value) when is_integer(value), do: %{"type" => "number"}
  defp property_schema(value) when is_float(value), do: %{"type" => "number"}
  defp property_schema(value) when is_boolean(value), do: %{"type" => "boolean"}
  defp property_schema(_value), do: %{"type" => "string"}

  defp transform_key(key, :identity), do: Atom.to_string(key)

  defp transform_key(key, :camel) do
    [head | tail] = key |> Atom.to_string() |> String.split("_")
    head <> Enum.map_join(tail, &String.capitalize/1)
  end
end
