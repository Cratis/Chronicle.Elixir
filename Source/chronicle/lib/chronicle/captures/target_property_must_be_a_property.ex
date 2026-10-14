# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Captures.TargetPropertyMustBeAProperty do
  @moduledoc """
  Raised at compile time when `set/2` targets a field that is not a property of the
  appended event's struct.
  """

  defexception [:message, :event_type, :property]

  @impl true
  def exception(opts) do
    event_type = Keyword.fetch!(opts, :event_type)
    property = Keyword.fetch!(opts, :property)

    %__MODULE__{
      event_type: event_type,
      property: property,
      message:
        "The target #{inspect(property)} for event type '#{inspect(event_type)}' must point to " <>
          "a property of its struct."
    }
  end
end
