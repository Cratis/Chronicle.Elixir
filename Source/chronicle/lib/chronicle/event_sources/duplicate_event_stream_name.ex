# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.EventSources.DuplicateEventStreamName do
  @moduledoc """
  Raised when an event source declares the same stream name more than once.
  """

  defexception [:event_source, :stream]

  @impl true
  def message(%{event_source: event_source, stream: stream}),
    do: "Event source #{event_source} declares the stream \"#{stream}\" more than once"
end
