# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Observers.GenerationDeliveryValidation do
  @moduledoc false

  # Rejects an ambiguous pin: with pinned generation delivery, an observer handling two
  # generations of the same event type id has no single generation to pin to.

  alias Chronicle.Observers.MultipleGenerationsOfEventTypeInObserver

  @doc false
  @spec validate!([module()]) :: :ok
  def validate!(event_type_modules) do
    duplicate =
      event_type_modules
      |> Enum.group_by(& &1.__chronicle_event_type__(:id))
      |> Enum.find(fn {_id, modules} ->
        modules |> Enum.map(& &1.__chronicle_event_type__(:generation)) |> Enum.uniq() |> length() >
          1
      end)

    case duplicate do
      {id, _modules} -> raise MultipleGenerationsOfEventTypeInObserver, event_type_id: id
      nil -> :ok
    end
  end
end
