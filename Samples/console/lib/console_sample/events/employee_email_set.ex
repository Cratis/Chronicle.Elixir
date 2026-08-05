# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule ConsoleSample.Events.EmployeeEmailSet do
  @moduledoc "An employee's email address has been set."

  use Chronicle.Events.EventType, id: "employee-email-set"

  defstruct [:email]

  # Scoped to :per_event_source_type — email uniqueness is checked only among
  # events observed from the same event source type (employees), not globally
  # across the whole event store. A customer or any other kind of event source
  # could use the same email value without tripping this constraint.
  unique(:email, ignore_casing: true, name: "employee-email", scope: :per_event_source_type)
end
