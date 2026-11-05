# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Observers.PerEventCallbackMissing do
  @moduledoc """
  Raised when an observer declares event types with `@handles` but does not define the
  per-event callback that receives them (`handle/2` for a reactor, `reduce/3` for a reducer).
  """

  defexception [:message, :observer, :callback]

  @impl true
  def exception(opts) do
    observer = Keyword.fetch!(opts, :observer)
    callback = Keyword.fetch!(opts, :callback)

    %__MODULE__{
      observer: observer,
      callback: callback,
      message: "#{inspect(observer)} declares @handles but does not define #{callback}."
    }
  end
end
