# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Captures.MissingCaptureSourceConfiguration do
  @moduledoc """
  Raised at compile time when a `Chronicle.Captures.Capture` declares no source
  (`api_source/2`, `webhook_source/1`, or `events_source/1`), or declares more than one.

  Exactly one source is required per capture.
  """

  defexception [:message, :capture, :count]

  @impl true
  def exception(opts) do
    capture = Keyword.fetch!(opts, :capture)
    count = Keyword.get(opts, :count, 0)

    message =
      case count do
        0 ->
          "Capture '#{capture}' must declare a source with api_source/2, webhook_source/1, " <>
            "or events_source/1."

        n ->
          "Capture '#{capture}' declares #{n} sources; exactly one is allowed. Use only one " <>
            "of api_source/2, webhook_source/1, or events_source/1."
      end

    %__MODULE__{capture: capture, count: count, message: message}
  end
end
