# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule ConsoleSample.Events.EmployeePromoted do
  @moduledoc "An employee has been promoted to a new title."

  use Chronicle.EventType, id: "employee-promoted"

  defstruct [:new_title]
end
