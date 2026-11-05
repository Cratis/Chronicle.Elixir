# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Observers.ObservesOnlyOnBatchFunctions do
  @moduledoc """
  Raised when `@observes` precedes a per-event callback (`handle/2`, `handle_replay/2` or
  `reduce/3`). `@observes` declares the event types of a batch function, which takes an
  `Chronicle.Observers.EventBatch`; give the batch function its own name.
  """

  defexception [:message, :observer, :function]

  @impl true
  def exception(opts) do
    observer = Keyword.fetch!(opts, :observer)
    function = Keyword.fetch!(opts, :function)

    %__MODULE__{
      observer: observer,
      function: function,
      message:
        "#{inspect(observer)}.#{function} is a per-event callback; @observes only goes on batch functions, which take a Chronicle.Observers.EventBatch."
    }
  end
end
