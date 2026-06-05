# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule ConsoleSample.Events.EmployeeAddressSet do
  @moduledoc "An employee's address has been set."

  use Chronicle.EventType, id: "employee-address-set"

  defstruct [:address, :city, :zip_code, :country]
end
