# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Events.EventTypeGenerationReferencesNonEventType do
  @moduledoc """
  Raised when `generation_for:` references a module that doesn't `use Chronicle.Events.EventType`.
  """

  defexception [:message, :module, :referenced_module]

  @impl true
  def exception(opts) do
    module = Keyword.fetch!(opts, :module)
    referenced_module = Keyword.fetch!(opts, :referenced_module)

    %__MODULE__{
      module: module,
      referenced_module: referenced_module,
      message:
        "'#{inspect(module)}' declares itself as a generation for '#{inspect(referenced_module)}', " <>
          "but '#{inspect(referenced_module)}' does not use Chronicle.Events.EventType. The module " <>
          "referenced by :generation_for must use Chronicle.Events.EventType directly."
    }
  end
end
