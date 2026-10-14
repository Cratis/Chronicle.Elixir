# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Observers.MultipleGenerationsOfEventTypeInObserver do
  @moduledoc """
  Raised when an observer with pinned generation delivery handles several generations of
  the same event type.

  With pinned generation delivery, Chronicle must send each generation to exactly one
  handled event type module; handling two generations of the same id makes that ambiguous.
  """

  defexception [:message, :event_type_id]

  @impl true
  def exception(opts) do
    event_type_id = Keyword.fetch!(opts, :event_type_id)

    %__MODULE__{
      event_type_id: event_type_id,
      message: "An observer cannot pin multiple generations of event type '#{event_type_id}'."
    }
  end
end
