# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule ConsoleSample.Projections.EmployeeDetails do
  @moduledoc """
  Model-bound projection — the projection definition lives directly inside the read model
  via `from` macros. The projection engine auto-maps properties with matching names; only
  `EmployeePromoted` needs an explicit mapping because the event field is `new_title`.
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

  from EmployeeHired
  from EmployeePromoted, set: [title: :new_title]
  from EmployeeAddressSet
  from EmployeeMoved
end
