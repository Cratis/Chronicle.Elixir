# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Imports.ImportProgress do
  @moduledoc """
  How far an import has come.

  Delivered to the process given as `:progress` to `Chronicle.Imports.import/2`, or
  subscribed with `Chronicle.Imports.observe/2`, as

      {:chronicle_import_progress, import_id, %Chronicle.Imports.ImportProgress{}}
  """

  alias Chronicle.Imports.ImportResult

  defstruct import_id: "",
            state: :open,
            events_received: 0,
            events_staged: 0,
            events_committed: 0,
            already_appended: 0,
            events_rejected: 0,
            chunks_acknowledged: 0,
            events_acknowledged: 0

  @type t :: %__MODULE__{
          import_id: String.t(),
          state: ImportResult.state(),
          events_received: non_neg_integer(),
          events_staged: non_neg_integer(),
          events_committed: non_neg_integer(),
          already_appended: non_neg_integer(),
          events_rejected: non_neg_integer(),
          chunks_acknowledged: non_neg_integer(),
          events_acknowledged: non_neg_integer()
        }
end
