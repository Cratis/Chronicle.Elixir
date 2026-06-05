# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Jobs.Job do
  @moduledoc """
  Represents the current state of a Chronicle job.
  """

  alias Chronicle.Jobs.{JobProgress, JobStatusChanged}

  defstruct id: "",
            details: "",
            type: "",
            status: :none,
            created_at: nil,
            status_changes: [],
            progress: %JobProgress{}

  @type t :: %__MODULE__{
          id: String.t(),
          details: String.t(),
          type: String.t(),
          status: atom(),
          created_at: DateTime.t() | nil,
          status_changes: [JobStatusChanged.t()],
          progress: JobProgress.t()
        }
end
