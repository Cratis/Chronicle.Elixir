# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Observers.ReducerMixesBatchAndPerEventFunctions do
  @moduledoc """
  Raised when a reducer declares a batch function and also per-event event types with
  `@handles`. A reducer either folds with `reduce/3` or with one batch function, never both.
  """

  defexception [:message, :observer]

  @impl true
  def exception(opts) do
    observer = Keyword.fetch!(opts, :observer)

    %__MODULE__{
      observer: observer,
      message:
        "#{inspect(observer)} has both a batch function and @handles for reduce/3; a reducer uses one or the other."
    }
  end
end
