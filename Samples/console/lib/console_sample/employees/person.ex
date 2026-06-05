# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule ConsoleSample.Employees.Person do
  @moduledoc """
  A single employee in the sample data set.
  """

  @type t :: %__MODULE__{
          id: String.t(),
          first_name: String.t(),
          last_name: String.t()
        }

  defstruct [:id, :first_name, :last_name]
end
