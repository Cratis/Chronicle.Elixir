# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule ConsoleSample.ReadModels.EmployeeState do
  @moduledoc "Employee read model produced by the reducer-backed sample."

  use Chronicle.ReadModels.ReadModel

  defstruct id: "",
            first_name: "",
            last_name: "",
            title: "",
            email: "",
            address: "",
            city: "",
            zip_code: "",
            country: ""
end
