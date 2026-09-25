# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule ConsoleSample.Projections.EmployeeListProjection do
  @moduledoc """
  Declarative projection that populates the `EmployeeList` read model from employee events.
  The projection definition lives in a separate module from the read model. The projection
  engine auto-maps properties with matching names; only `EmployeePromoted` needs an explicit
  mapping because the event field is `new_title`.
  """

  use Chronicle.Projections.Projection, model: ConsoleSample.ReadModels.EmployeeList

  alias ConsoleSample.Events.{EmployeeHired, EmployeePromoted}

  from EmployeeHired
  from EmployeePromoted, set: [title: :new_title]
end
