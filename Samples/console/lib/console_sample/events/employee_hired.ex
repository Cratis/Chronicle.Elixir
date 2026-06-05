# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule ConsoleSample.Events.EmployeeHired do
  @moduledoc "An employee has been hired into the organization."

  use Chronicle.EventType, id: "employee-hired"

  defstruct [:first_name, :last_name, :title]

  unique_event_type()
end
