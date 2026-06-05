# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Jobs.JobStepStatusChanged do
  @moduledoc """
  Represents a status transition for a Chronicle job step.
  """

  defstruct status: :unknown,
            occurred: nil,
            exception_messages: [],
            exception_stack_trace: ""

  @type t :: %__MODULE__{
          status: atom(),
          occurred: DateTime.t() | nil,
          exception_messages: [String.t()],
          exception_stack_trace: String.t()
        }
end
