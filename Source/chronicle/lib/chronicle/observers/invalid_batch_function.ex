# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Observers.InvalidBatchFunction do
  @moduledoc """
  Raised when a batch function has the wrong shape: a reactor batch function takes
  `(batch, context)`, a reducer batch function takes `(batch, current, context)`.
  """

  defexception [:message, :observer, :function, :expected]

  @impl true
  def exception(opts) do
    observer = Keyword.fetch!(opts, :observer)
    function = Keyword.fetch!(opts, :function)
    expected = Keyword.fetch!(opts, :expected)

    %__MODULE__{
      observer: observer,
      function: function,
      expected: expected,
      message: "#{inspect(observer)}.#{function} is not a valid batch function: #{expected}"
    }
  end
end
