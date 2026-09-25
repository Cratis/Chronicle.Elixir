# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule ConsoleSample.Projections.EmployeeListProjection do
  @moduledoc """
  Declarative projection that populates the `EmployeeList` read model from employee events.
  The projection definition lives in a separate module from the read model. The projection
  engine auto-maps properties with matching single-word names such as `title`. Multi-word
  fields are mapped with their camelCase wire names, because in cratis_chronicle 3.5.0
  neither auto-mapping nor atom expressions such as `:first_name` resolve them.
  """

  use Chronicle.Projections.Projection, model: ConsoleSample.ReadModels.EmployeeList

  alias ConsoleSample.Events.{EmployeeHired, EmployeePromoted}

  from EmployeeHired, set: [first_name: "firstName", last_name: "lastName"]
  from EmployeePromoted, set: [title: "newTitle"]
end
