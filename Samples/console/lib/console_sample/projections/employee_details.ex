# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule ConsoleSample.Projections.EmployeeDetails do
  @moduledoc """
  Model-bound projection — the projection definition lives directly inside the read model
  via `from` macros. The projection engine auto-maps properties with matching single-word
  names such as `title` and `city`.

  Multi-word fields are mapped explicitly with their camelCase wire names: events travel as
  camelCase JSON, and in cratis_chronicle 3.5.0 neither auto-mapping nor atom expressions
  such as `:first_name` resolve them.
  """

  use Chronicle.ReadModels.ReadModel

  alias ConsoleSample.Events.{
    EmployeeAddressSet,
    EmployeeHired,
    EmployeeMoved,
    EmployeePromoted
  }

  defstruct id: "",
            first_name: "",
            last_name: "",
            title: "",
            address: "",
            city: "",
            zip_code: "",
            country: ""

  from EmployeeHired, set: [first_name: "firstName", last_name: "lastName"]
  from EmployeePromoted, set: [title: "newTitle"]
  from EmployeeAddressSet, set: [zip_code: "zipCode"]
  from EmployeeMoved, set: [zip_code: "zipCode"]
end
