# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule ConsoleSample.Events.EmployeeMoved do
  @moduledoc "An employee has relocated to a new address."

  use Cratis.Chronicle.Events.EventType, id: "employee-moved"

  defstruct [:address, :city, :zip_code, :country]
end
