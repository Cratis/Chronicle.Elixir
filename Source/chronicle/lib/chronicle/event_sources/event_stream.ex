# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.EventSources.EventStream do
  @moduledoc """
  A named stream declared by an event source.

  The stream name is written as the event stream type of events appended to it.
  A stream that declares no concurrency dimensions inherits those of its event
  source.
  """

  alias Chronicle.EventSources.ConcurrencyDimensions

  @enforce_keys [:name]
  defstruct [:name, description: "", concurrency: []]

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          concurrency: ConcurrencyDimensions.t()
        }
end
