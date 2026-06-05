# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Jobs.JobStep do
  @moduledoc """
  Represents the current state of a Chronicle job step.
  """

  alias Chronicle.Jobs.{JobStepProgress, JobStepStatusChanged}

  defstruct id: "",
            type: "",
            name: "",
            status: :unknown,
            status_changes: [],
            progress: %JobStepProgress{}

  @type t :: %__MODULE__{
          id: String.t(),
          type: String.t(),
          name: String.t(),
          status: atom(),
          status_changes: [JobStepStatusChanged.t()],
          progress: JobStepProgress.t()
        }
end
