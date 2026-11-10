# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Projections.DictionaryKeys do
  @moduledoc false

  # Builds the read-model property path of a dictionary entry whose key comes from the event being
  # projected. The kernel recognizes three dynamic key segments after the dictionary property:
  #
  #   prices.$eventContent.sku        — a property of the event content (case-sensitive)
  #   event_counts.$eventContext.type — a property of the event context
  #   edits.$causedBy.userName        — the identity that caused the event
  #
  # These are the exact paths the .NET client emits (ProjectionPropertyPaths.DictionaryEntry), so
  # the kernel accepts them at registration.

  alias Chronicle.Registration.Coordinator

  @caused_by_properties %{subject: "subject", name: "name", user_name: "userName"}

  @typedoc "Where the key of a dictionary entry comes from."
  @type key_source ::
          {:event_content, atom() | String.t()}
          | {:event_context, atom() | String.t()}
          | {:caused_by, :subject | :name | :user_name}

  @doc """
  Returns `true` when `value` names the key of a dictionary entry.
  """
  @spec key_source?(term()) :: boolean()
  def key_source?({:event_content, path}) when is_atom(path) or is_binary(path), do: true
  def key_source?({:event_context, path}) when is_atom(path) or is_binary(path), do: true

  def key_source?({:caused_by, property}),
    do: Map.has_key?(@caused_by_properties, property)

  def key_source?(_value), do: false

  @doc """
  Returns the property path of the entry of dictionary `field` keyed by `key_source`.

  Event content keys travel as camelCase JSON, so an atom such as `:product_sku` names the
  `productSku` event property. A string is used exactly as written, for a nested path such as
  `"customer.id"`. Event context keys keep the form earlier versions of this client sent.
  """
  @spec entry_path(atom() | String.t(), key_source()) :: String.t()
  def entry_path(field, key_source), do: "#{field}.#{segment(key_source)}"

  defp segment({:event_content, path}) when is_atom(path),
    do: "$eventContent.#{path |> Atom.to_string() |> Coordinator.camelize()}"

  defp segment({:event_content, path}) when is_binary(path), do: "$eventContent.#{path}"
  defp segment({:event_context, path}), do: "$eventContext.#{path}"

  defp segment({:caused_by, property} = key_source) do
    case Map.fetch(@caused_by_properties, property) do
      {:ok, name} ->
        "$causedBy.#{name}"

      :error ->
        raise ArgumentError, invalid_key_source_message(key_source)
    end
  end

  defp segment(key_source), do: raise(ArgumentError, invalid_key_source_message(key_source))

  @doc false
  @spec invalid_key_source_message(term()) :: String.t()
  def invalid_key_source_message(key_source) do
    "#{inspect(key_source)} is not a dictionary key; use {:event_content, :property}, " <>
      "{:event_context, :property} or {:caused_by, :subject | :name | :user_name}"
  end
end
