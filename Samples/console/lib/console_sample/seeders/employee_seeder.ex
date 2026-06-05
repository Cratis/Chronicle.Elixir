# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule ConsoleSample.Seeders.EmployeeSeeder do
  @moduledoc "Seeds the three employees used by the interactive sample."

  use Chronicle.Seeding.Seeder

  alias ConsoleSample.Employees
  alias ConsoleSample.Events.{EmployeeAddressSet, EmployeeEmailSet, EmployeeHired}

  @addresses [
    %{address: "221B Baker Street", city: "London", zip_code: "NW1 6XE", country: "UK"},
    %{
      address: "1600 Amphitheatre Parkway",
      city: "Mountain View",
      zip_code: "94043",
      country: "USA"
    },
    %{address: "1 Infinite Loop", city: "Cupertino", zip_code: "95014", country: "USA"}
  ]

  @titles ["Software Engineer", "Senior Engineer", "Principal Engineer"]

  @impl true
  def seed(builder) do
    Employees.all()
    |> Enum.with_index()
    |> Enum.reduce(builder, fn {employee, index}, acc ->
      address = Enum.at(@addresses, rem(index, length(@addresses)))
      title = Enum.at(@titles, rem(index, length(@titles)))

      Chronicle.Seeding.for_event_source(acc, employee.id, [
        %EmployeeHired{
          first_name: employee.first_name,
          last_name: employee.last_name,
          title: title
        },
        %EmployeeEmailSet{email: Employees.email_for(employee)},
        %EmployeeAddressSet{
          address: address.address,
          city: address.city,
          zip_code: address.zip_code,
          country: address.country
        }
      ])
    end)
  end
end
