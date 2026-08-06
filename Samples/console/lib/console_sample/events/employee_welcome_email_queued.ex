# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule ConsoleSample.Events.EmployeeWelcomeEmailQueued do
  @moduledoc """
  A welcome email has been queued for a newly hired employee.

  Appended as a reactor side effect from `ConsoleSample.Reactors.HrNotificationReactor`
  in response to `EmployeeHired` — see that module for how `handle/2` triggers it.
  """

  use Chronicle.Events.EventType, id: "employee-welcome-email-queued"

  defstruct [:template]
end
