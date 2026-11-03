# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Observers.ReducerHasMoreThanOneBatchFunction do
  @moduledoc """
  Raised when a reducer declares more than one batch function. A reducer is a single fold over
  one event source's events, so it has at most one batch function.
  """

  defexception [:message, :observer]

  @impl true
  def exception(opts) do
    observer = Keyword.fetch!(opts, :observer)

    %__MODULE__{
      observer: observer,
      message: "#{inspect(observer)} has more than one batch function; a reducer has at most one."
    }
  end
end
