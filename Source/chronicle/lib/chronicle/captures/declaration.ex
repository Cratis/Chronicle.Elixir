# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Captures.Declaration do
  @moduledoc """
  Renders a capture definition to Capture Declaration Language (CDL) text.

  See the shared [Capture Declaration Language](https://github.com/Cratis/Chronicle/blob/main/Documentation/captures/capture-declaration-language/grammar.md)
  grammar for the language this renders.
  """

  import Bitwise

  # Fixed namespace for deriving a deterministic capture id (UUIDv5) from a capture module's
  # name, so re-registering a capture under the same module updates the same kernel-side record
  # instead of creating a new one every time.
  @id_namespace "e1c1c2f9-1d74-46ce-8caf-ddc1247493d4"

  @type source ::
          {:api, String.t(), keyword()}
          | {:webhook, String.t(), keyword()}
          | {:events, [String.t()]}

  @type map_operation ::
          {:rename, String.t(), String.t()}
          | {:template, String.t(), String.t()}
          | {:translate, String.t(), String.t(), [{String.t(), String.t()}]}
          | {:split, String.t(), String.t(), [String.t()]}

  @type when_clause ::
          :added
          | :removed
          | {:property, String.t()}
          | {:any, [String.t()]}
          | {:all, [String.t()]}
          | {:transition, String.t(), String.t(), String.t()}
          | {:expression, String.t()}

  @type append :: {String.t(), when_clause(), [{String.t(), String.t()}]}
  @type nested :: {String.t(), [map_operation()] | nil, [append()]}
  @type children :: {String.t(), String.t(), [map_operation()] | nil, [append()]}

  @type t :: %{
          name: String.t(),
          source: source(),
          key: String.t(),
          map: [map_operation()] | nil,
          appends: [append()],
          nested: [nested()],
          children: [children()]
        }

  @doc """
  Renders a capture definition map to CDL text.
  """
  @spec render(t()) :: String.t()
  def render(%{
        name: name,
        source: source,
        key: key,
        map: map_ops,
        appends: appends,
        nested: nested,
        children: children
      }) do
    lines =
      ["capture #{name}"] ++
        indent(render_source(source), 1) ++
        indent(["key #{key}"], 1) ++
        indent(render_map(map_ops), 1) ++
        indent(Enum.flat_map(appends, &render_append/1), 1) ++
        indent(Enum.flat_map(nested, &render_nested/1), 1) ++
        indent(Enum.flat_map(children, &render_children/1), 1)

    Enum.join(lines, "\n") <> "\n"
  end

  @doc """
  Derives a deterministic UUIDv5 capture id from a capture module's name.
  """
  @spec deterministic_id(module()) :: String.t()
  def deterministic_id(module) when is_atom(module) do
    name = to_string(module)
    namespace_bytes = @id_namespace |> String.replace("-", "") |> Base.decode16!(case: :mixed)

    <<hash::binary-size(16), _rest::binary>> = :crypto.hash(:sha, namespace_bytes <> name)

    hash
    |> set_version_and_variant()
    |> format_uuid()
  end

  defp render_source({:api, api, opts}) do
    properties =
      ["api #{api}"] ++
        maybe_property("route", opts[:route]) ++ maybe_property("poll", opts[:poll])

    ["source api"] ++ indent(properties, 1)
  end

  defp render_source({:webhook, path, _opts}) do
    ["source webhook"] ++ indent(["path #{path}"], 1)
  end

  defp render_source({:events, events}) do
    ["source events"] ++ indent(Enum.map(events, &"from #{&1}"), 1)
  end

  defp maybe_property(_name, nil), do: []
  defp maybe_property(name, value), do: ["#{name} #{value}"]

  defp render_map(nil), do: []
  defp render_map([]), do: []

  defp render_map(operations) do
    ["map"] ++ indent(Enum.flat_map(operations, &render_map_operation/1), 1)
  end

  defp render_map_operation({:rename, target, source}), do: ["#{target} = #{source}"]

  defp render_map_operation({:template, target, template}),
    do: ["#{target} = `#{template}`"]

  defp render_map_operation({:translate, target, source, entries}) do
    entry_lines = Enum.map(entries, fn {from, to} -> "#{quoted(from)} => #{quoted(to)}" end)
    ["#{target} = #{source} translate"] ++ indent(entry_lines, 1)
  end

  defp render_map_operation({:split, source, delimiter, into}) do
    ["split #{source} by #{quoted(delimiter)}"] ++ indent(into, 1)
  end

  defp render_append({event_type, when_clause, assignments}) do
    assignment_lines = Enum.map(assignments, fn {field, value} -> "#{field} = #{value}" end)

    ["append #{event_type}"] ++
      indent(["when #{render_when(when_clause)}"] ++ assignment_lines, 1)
  end

  defp render_when(:added), do: "added"
  defp render_when(:removed), do: "removed"
  defp render_when({:property, property}), do: property
  defp render_when({:any, properties}), do: Enum.join(properties, " or ")
  defp render_when({:all, properties}), do: Enum.join(properties, " and ")

  defp render_when({:transition, property, from, to}),
    do: "#{property} from #{quoted(from)} to #{quoted(to)}"

  defp render_when({:expression, expression}), do: "`#{expression}`"

  defp render_nested({object_path, map_ops, appends}) do
    body = render_map(map_ops) ++ Enum.flat_map(appends, &render_append/1)
    ["nested #{object_path}"] ++ indent(body, 1)
  end

  defp render_children({collection_path, identified_by, map_ops, appends}) do
    body = render_map(map_ops) ++ Enum.flat_map(appends, &render_append/1)
    ["children #{collection_path} identified by #{identified_by}"] ++ indent(body, 1)
  end

  defp indent(lines, level) do
    prefix = String.duplicate("  ", level)
    Enum.map(lines, &(prefix <> &1))
  end

  defp quoted(value), do: "\"#{value}\""

  defp set_version_and_variant(<<a::32, b::16, c::16, d::8, e::8, rest::binary-size(6)>>) do
    c = (c &&& 0x0FFF) ||| 0x5000
    d = (d &&& 0x3F) ||| 0x80
    <<a::32, b::16, c::16, d::8, e::8, rest::binary>>
  end

  defp format_uuid(<<a::32, b::16, c::16, d::8, e::8, rest::binary-size(6)>>) do
    [
      a |> Integer.to_string(16) |> String.pad_leading(8, "0"),
      b |> Integer.to_string(16) |> String.pad_leading(4, "0"),
      c |> Integer.to_string(16) |> String.pad_leading(4, "0"),
      (d * 256 + e) |> Integer.to_string(16) |> String.pad_leading(4, "0"),
      Base.encode16(rest, case: :lower)
    ]
    |> Enum.join("-")
    |> String.downcase()
  end
end
