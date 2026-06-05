# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.WebHooks.EventType do
  @moduledoc """
  Represents an event type referenced by a webhook definition.
  """

  defstruct id: "", generation: 1

  @type t :: %__MODULE__{
          id: String.t(),
          generation: pos_integer()
        }
end
