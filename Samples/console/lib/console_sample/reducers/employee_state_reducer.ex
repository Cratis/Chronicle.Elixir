# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule ConsoleSample.Reducers.EmployeeStateReducer do
  @moduledoc "Folds employee lifecycle events into the EmployeeState read model."

  use Chronicle.Reducers.Reducer, model: ConsoleSample.ReadModels.EmployeeState

  alias ConsoleSample.Events.{
    EmployeeAddressSet,
    EmployeeEmailSet,
    EmployeeHired,
    EmployeeMoved,
    EmployeePromoted
  }

  alias ConsoleSample.ReadModels.EmployeeState

  @handles EmployeeHired
  @handles EmployeeAddressSet
  @handles EmployeeEmailSet
  @handles EmployeePromoted
  @handles EmployeeMoved

  @impl true
  def reduce(%EmployeeHired{} = event, _model, context) do
    %EmployeeState{
      id: context.event_source_id,
      first_name: event.first_name,
      last_name: event.last_name,
      title: event.title
    }
  end

  def reduce(%EmployeeAddressSet{} = event, model, context) do
    update_address(model, context, event)
  end

  def reduce(%EmployeeEmailSet{} = event, model, context) do
    %{base_state(model, context) | email: event.email}
  end

  def reduce(%EmployeePromoted{} = event, model, context) do
    %{base_state(model, context) | title: event.new_title}
  end

  def reduce(%EmployeeMoved{} = event, model, context) do
    update_address(model, context, event)
  end

  defp update_address(model, context, event) do
    %{
      base_state(model, context)
      | address: event.address,
        city: event.city,
        zip_code: event.zip_code,
        country: event.country
    }
  end

  defp base_state(nil, context), do: %EmployeeState{id: context.event_source_id}
  defp base_state(model, _context), do: model
end
