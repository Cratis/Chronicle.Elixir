# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Discovery.DefaultedIdWarning do
  @moduledoc """
  Warns, at most once per module for the lifetime of the BEAM node, that a reactor, reducer
  or projection is relying on its module name as its identifier.

  Renaming or moving the module then silently resets Chronicle's observation position for
  it, because the id changes along with the name. Discovery can run more than once in a
  client's lifetime (once while logging at startup, again through
  `Chronicle.Client.discovery_report/1` or `mix chronicle.discover`), so the warning is kept
  behind a `:persistent_term` guard keyed by module rather than emitted unconditionally.
  """

  require Logger

  @doc """
  Emits the one-time warning for `module` when its id was defaulted and warnings are enabled.

  `kind` is `:reactor`, `:reducer` or `:projection` — only those three default an id from the
  module name today. `warn?` is the client's `warn_defaulted_ids` option; passing `false`
  suppresses the warning (and skips the `:persistent_term` write) without otherwise affecting
  discovery.
  """
  @spec warn_once(module(), :reactor | :reducer | :projection, boolean()) :: :ok
  def warn_once(_module, _kind, false), do: :ok

  def warn_once(module, kind, true) do
    key = {__MODULE__, module}

    case :persistent_term.get(key, :not_warned) do
      :warned ->
        :ok

      :not_warned ->
        :persistent_term.put(key, :warned)
        Logger.warning(message(module, kind))
        :ok
    end
  end

  defp message(module, kind) do
    use_module =
      case kind do
        :reactor -> "Chronicle.Reactors.Reactor"
        :reducer -> "Chronicle.Reducers.Reducer"
        :projection -> "Chronicle.Projections.Projection"
      end

    "#{inspect(module)} has no explicit :id and defaults to its module name. Renaming or " <>
      "moving this module will silently reset its observation position. Pin the id with " <>
      "`use #{use_module}, id: \"...\", ...`."
  end
end
