# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Jobs.JobStepProgress do
  @moduledoc """
  Represents progress for an individual Chronicle job step.
  """

  defstruct percentage: 0, message: ""

  @type t :: %__MODULE__{
          percentage: non_neg_integer(),
          message: String.t()
        }
end
