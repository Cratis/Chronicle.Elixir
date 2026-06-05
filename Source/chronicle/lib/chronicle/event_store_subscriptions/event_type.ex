# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.EventStoreSubscriptions.EventType do
  @moduledoc """
  Represents an event type included in an event store subscription definition.
  """

  defstruct id: "", generation: 1, tombstone?: false

  @type t :: %__MODULE__{
          id: String.t(),
          generation: pos_integer(),
          tombstone?: boolean()
        }
end
