# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Jobs.JobProgress do
  @moduledoc """
  Represents aggregate progress for a Chronicle job.
  """

  defstruct total_steps: 0,
            successful_steps: 0,
            failed_steps: 0,
            stopped_steps: 0,
            completed?: false,
            stopped?: false,
            message: ""

  @type t :: %__MODULE__{
          total_steps: non_neg_integer(),
          successful_steps: non_neg_integer(),
          failed_steps: non_neg_integer(),
          stopped_steps: non_neg_integer(),
          completed?: boolean(),
          stopped?: boolean(),
          message: String.t()
        }
end
