# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule ConsoleSample.Reducers.CustomerReducer do
  @moduledoc "Builds the customer read model used for the compliance demonstration."

  use Chronicle.Reducer, model: ConsoleSample.ReadModels.Customer

  alias ConsoleSample.Events.{CustomerAddressUpdated, CustomerRegistered}
  alias ConsoleSample.ReadModels.Customer

  @handles CustomerRegistered
  @handles CustomerAddressUpdated

  @impl true
  def reduce(%CustomerRegistered{} = event, _model, context) do
    %Customer{
      id: context.event_source_id,
      full_name: event.full_name,
      email: event.email,
      phone_number: event.phone_number,
      customer_number: "CUST-#{String.slice(context.event_source_id, 0, 8)}",
      account_status: "active",
      total_orders: 0
    }
  end

  def reduce(%CustomerAddressUpdated{} = event, model, context) do
    %{
      base_state(model, context)
      | street_address: event.street_address,
        city: event.city,
        postal_code: event.postal_code,
        country: event.country
    }
  end

  defp base_state(nil, context), do: %Customer{id: context.event_source_id}
  defp base_state(model, _context), do: model
end
