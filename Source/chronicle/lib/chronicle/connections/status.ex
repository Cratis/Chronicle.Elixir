# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Connections.Status do
  @moduledoc false

  # Do not expose a live channel or stream (and its credential and headers) in
  # :sys.get_status/1 or in the GenServer crash report's last message/log.
  def redact(%{state: state} = status, replacements) do
    status
    |> Map.put(:state, Map.merge(state, Map.new(replacements)))
    |> Map.replace_lazy(:message, fn _ -> :redacted end)
    |> Map.replace_lazy(:log, fn _ -> :redacted end)
  end
end
