# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule ConsoleSample.Events.EmployeeEmailSet do
  @moduledoc "An employee's email address has been set."

  use Chronicle.EventType, id: "employee-email-set"

  defstruct [:email]

  unique(:email, ignore_casing: true, name: "employee-email")
end
