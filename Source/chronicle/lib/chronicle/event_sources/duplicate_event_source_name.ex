# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.EventSources.DuplicateEventSourceName do
  @moduledoc """
  Raised when more than one event source definition uses the same name.
  """

  defexception [:name, :modules]

  @impl true
  def message(%{name: name, modules: modules}),
    do:
      "Event source name \"#{name}\" is declared by more than one module: #{Enum.map_join(modules, ", ", &inspect/1)}"
end
