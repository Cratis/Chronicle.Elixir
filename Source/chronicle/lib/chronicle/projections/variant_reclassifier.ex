# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Projections.VariantReclassifier do
  @moduledoc false

  # Turns an ordinary ProjectionDefinition into one variant of a mutually exclusive group,
  # shared by the model-bound (Chronicle.ReadModels.ReadModel) and declarative
  # (Chronicle.Projections.Projection) authoring paths so both express variants the same way.
  #
  # A variant compiles to an ordinary, independent ProjectionDefinition. What makes it a variant
  # is which of its handlers may create it: only the enters_on event(s) keep their
  # create-or-update From handler, and everything else - whether declared directly or merged in
  # from a Chronicle.Projections.GlobalHandler - becomes an update-only, self-referential Join
  # keyed by the variant's own key. A join never creates a document, so no other event can
  # create the variant or resurrect the entity into one it has since left. Mutual exclusion is
  # then expressed with the ordinary RemovedWith mechanism, against every sibling's entering
  # event(s).

  alias Chronicle.Projections.GlobalHandlerPropertyNotOnVariant
  alias Chronicle.Projections.VariantMustDeclareEntersOnEvent
  alias Chronicle.Registration.Coordinator

  alias Cratis.Chronicle.Contracts.Projections.{
    FromDefinition,
    JoinDefinition,
    KeyValuePair_EventType_FromDefinition,
    KeyValuePair_EventType_JoinDefinition,
    KeyValuePair_EventType_RemovedWithDefinition,
    RemovedWithDefinition
  }

  @event_source_id_key "$eventSourceId"

  @doc """
  Applies global-handler merging, reclassification, and mutual-exclusion cross-wiring to every
  entry that declared a variant, then returns just the (possibly modified) ProjectionDefinition
  list, in the original order.

  Each entry is `{module, member_source_module, definition, variant}`, where `member_source_module`
  is the module whose struct defines the read model's actual fields (itself, for a model-bound
  read model; the projected-onto read model module, for a declarative projection), and `variant`
  is `nil` for an ordinary projection or
  `%{identity: module, key: atom, entering_event_types: [EventType]}` for a variant.
  """
  def apply(entries, global_handlers) do
    entries
    |> Enum.map(&merge_global_handlers(&1, global_handlers))
    |> Enum.map(&reclassify/1)
    |> cross_wire_groups()
    |> Enum.map(fn {_module, _member_source, definition, _variant} -> definition end)
  end

  defp merge_global_handlers({module, member_source, definition, nil}, _global_handlers),
    do: {module, member_source, definition, nil}

  defp merge_global_handlers({module, member_source, definition, variant}, global_handlers) do
    matching =
      Enum.filter(global_handlers, fn handler ->
        handler.__chronicle_global_handler__(:identity) == variant.identity
      end)

    if matching == [] do
      {module, member_source, definition, variant}
    else
      member_names = member_names_for(member_source)

      merged_from =
        Enum.reduce(matching, Map.get(definition, :From), fn handler, from_acc ->
          Enum.reduce(handler.__chronicle_global_handler__(:from), from_acc, fn {event_module,
                                                                                 opts},
                                                                                acc ->
            properties = Coordinator.build_properties(opts)

            Enum.each(properties, fn {property, _expression} ->
              unless MapSet.member?(member_names, property) do
                raise GlobalHandlerPropertyNotOnVariant,
                  handler_module: handler,
                  variant_module: module,
                  property: property
              end
            end)

            merge_from_entry(acc, Coordinator.proto_event_type(event_module), properties)
          end)
        end)

      {module, member_source, %{definition | From: merged_from}, variant}
    end
  end

  defp merge_from_entry(from_entries, event_type, properties) do
    case Enum.find_index(from_entries, fn entry -> Map.get(entry, :Key) == event_type end) do
      nil ->
        from_entries ++
          [
            struct(KeyValuePair_EventType_FromDefinition,
              Key: event_type,
              Value:
                struct(FromDefinition,
                  Key: @event_source_id_key,
                  Properties: properties,
                  ParentKey: ""
                )
            )
          ]

      index ->
        List.update_at(from_entries, index, fn entry ->
          value = Map.get(entry, :Value)
          merged_properties = Map.merge(Map.get(value, :Properties), properties)
          %{entry | Value: %{value | Properties: merged_properties}}
        end)
    end
  end

  defp member_names_for(module) do
    module.__struct__()
    |> Map.from_struct()
    |> Map.keys()
    |> Enum.map(&Atom.to_string/1)
    |> MapSet.new()
  end

  defp reclassify({module, member_source, definition, nil}),
    do: {module, member_source, definition, nil}

  defp reclassify({module, member_source, definition, variant}) do
    if Enum.empty?(variant.entering_event_types) do
      raise VariantMustDeclareEntersOnEvent, variant_module: module
    end

    entering = MapSet.new(variant.entering_event_types)

    {remaining_from, reclassified_joins} =
      Enum.reduce(Map.get(definition, :From), {[], []}, fn entry, {from_acc, join_acc} ->
        if MapSet.member?(entering, Map.get(entry, :Key)) do
          {from_acc ++ [entry], join_acc}
        else
          entry_value = Map.get(entry, :Value)

          entry_key =
            case Map.get(entry_value, :Key) do
              nil -> @event_source_id_key
              "" -> @event_source_id_key
              key -> key
            end

          join =
            struct(KeyValuePair_EventType_JoinDefinition,
              Key: Map.get(entry, :Key),
              Value:
                struct(JoinDefinition,
                  On: to_string(variant.key),
                  Key: entry_key,
                  Properties: Map.get(entry_value, :Properties)
                )
            )

          {from_acc, join_acc ++ [join]}
        end
      end)

    updated_definition = %{
      definition
      | From: remaining_from,
        Join: Map.get(definition, :Join) ++ reclassified_joins
    }

    {module, member_source, updated_definition, variant}
  end

  defp cross_wire_groups(entries) do
    by_identity =
      entries
      |> Enum.filter(fn {_m, _ms, _d, variant} -> variant != nil end)
      |> Enum.group_by(fn {_m, _ms, _d, variant} -> variant.identity end)

    Enum.map(entries, fn
      {module, member_source, definition, nil} ->
        {module, member_source, definition, nil}

      {module, member_source, definition, variant} = entry ->
        siblings =
          by_identity
          |> Map.get(variant.identity, [])
          |> Enum.reject(fn {sibling_module, _, _, _} -> sibling_module == module end)

        if siblings == [] do
          entry
        else
          existing_keys =
            MapSet.new(Enum.map(Map.get(definition, :RemovedWith), &Map.get(&1, :Key)))

          new_removed_with =
            siblings
            |> Enum.flat_map(fn {_sm, _sms, _sd, sibling} -> sibling.entering_event_types end)
            |> Enum.uniq()
            |> Enum.reject(&MapSet.member?(existing_keys, &1))
            |> Enum.map(fn event_type ->
              struct(KeyValuePair_EventType_RemovedWithDefinition,
                Key: event_type,
                Value:
                  struct(RemovedWithDefinition,
                    Key: @event_source_id_key,
                    ParentKey: @event_source_id_key
                  )
              )
            end)

          updated_removed_with = Map.get(definition, :RemovedWith) ++ new_removed_with
          {module, member_source, %{definition | RemovedWith: updated_removed_with}, variant}
        end
    end)
  end
end
