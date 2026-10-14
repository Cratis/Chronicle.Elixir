# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Events.EventTypeGenerationForCannotBeCombinedWithEventType do
  @moduledoc """
  Raised when a module gives both `:id` and `:generation_for` to `use Chronicle.Events.EventType`.

  A module is either the current event type (`:id`) or a previous generation of one
  (`:generation_for`), not both.
  """

  defexception [:message, :module]

  @impl true
  def exception(opts) do
    module = Keyword.fetch!(opts, :module)

    %__MODULE__{
      module: module,
      message:
        "'#{inspect(module)}' is given both :id and :generation_for. A module is either the " <>
          "current event type or a previous generation of one, not both."
    }
  end
end
