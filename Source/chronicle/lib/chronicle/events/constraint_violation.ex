# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Events.ConstraintViolation do
  @moduledoc """
  Helpers for working with a constraint violation returned on an
  `t:Chronicle.EventSequences.AppendResult.constraint_violation/0` or the raw wire violation
  passed to a `:message` callback (see `Chronicle.Events.EventType.unique/2`,
  `Chronicle.Events.EventType.unique_event_type/1`, and `Chronicle.Events.Constraint`).

  A violation's `:details` (or `:Details` on the raw wire shape) is a plain string-keyed map.
  `details/1` maps the keys Chronicle itself assigns a meaning to onto atoms, mirroring the C#
  client's `WellKnownConstraintDetailKeys`, while leaving every other key as-is.
  """

  @well_known %{
    "PropertyName" => :property_name,
    "PropertyValue" => :property_value,
    "ClosedBy" => :closed_by,
    "ClosedAtSequenceNumber" => :closed_at_sequence_number
  }

  @doc """
  Returns a violation's details with well-known keys mapped to atoms:

    * `:property_name` — the name of the offending property
    * `:property_value` — the value the offending property carried (a PII property carries its
      encrypted form, since constraints are validated after compliance is applied)
    * `:closed_by` — the owner of the closure rejecting the append
    * `:closed_at_sequence_number` — the sequence number at which the scope was closed

  A key without a well-known mapping is kept as its original string key, so no detail is lost.
  Accepts either a resolved violation map (`:details`) or the raw wire shape (`:Details`).
  """
  @spec details(map()) :: map()
  def details(violation) when is_map(violation) do
    violation
    |> Map.get(:Details, Map.get(violation, :details, %{}))
    |> details_map()
  end

  def details(_violation), do: %{}

  defp details_map(details) when is_map(details) do
    Map.new(details, fn {key, value} -> {Map.get(@well_known, to_string(key), key), value} end)
  end

  defp details_map(_details), do: %{}
end
