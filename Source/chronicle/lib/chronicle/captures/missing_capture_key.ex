# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Captures.MissingCaptureKey do
  @moduledoc """
  Raised at compile time when a `Chronicle.Captures.Capture` does not declare a `key/1`.

  A capture key is required to identify and diff items from the source.
  """

  defexception [:message, :capture]

  @impl true
  def exception(opts) do
    capture = Keyword.fetch!(opts, :capture)

    %__MODULE__{
      capture: capture,
      message: "Capture '#{capture}' must declare a key with key/1 before it can be compiled."
    }
  end
end
