# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Observers.BatchFunctionObservesUnknownEventType do
  @moduledoc """
  Raised when a batch function declares `@observes` with a module that is not an event type
  (a module that does not `use Chronicle.Events.EventType`).
  """

  defexception [:message, :observer, :function, :event_type]

  @impl true
  def exception(opts) do
    observer = Keyword.fetch!(opts, :observer)
    function = Keyword.fetch!(opts, :function)
    event_type = Keyword.fetch!(opts, :event_type)

    %__MODULE__{
      observer: observer,
      function: function,
      event_type: event_type,
      message:
        "#{inspect(observer)}.#{function} observes #{inspect(event_type)}, which is not an event type."
    }
  end
end
