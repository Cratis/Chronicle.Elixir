# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Observers.EventTypeObservedByMoreThanOneFunction do
  @moduledoc """
  Raised when an event type would reach more than one function of an observer: two batch
  functions observe it, or a batch function observes it and it is also declared with `@handles`
  for the per-event callback. Each event type reaches exactly one function.
  """

  defexception [:message, :observer, :event_type]

  @impl true
  def exception(opts) do
    observer = Keyword.fetch!(opts, :observer)
    event_type = Keyword.fetch!(opts, :event_type)

    %__MODULE__{
      observer: observer,
      event_type: event_type,
      message:
        "#{inspect(event_type)} reaches more than one function of #{inspect(observer)}; each event type must reach exactly one function."
    }
  end
end
