# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Imports.ImportRejection do
  @moduledoc """
  An event of an import that was not staged or not committed.

  `index` counts from zero in the order the events were added to the import, so it points
  back into the source the events were read from.
  """

  defstruct index: 0, event_type: "", reasons: []

  @type t :: %__MODULE__{
          index: non_neg_integer(),
          event_type: String.t(),
          reasons: [String.t()]
        }
end
