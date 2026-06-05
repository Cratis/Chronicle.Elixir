# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule ConsoleSample.Events.CustomerRegistered do
  @moduledoc "Registers a customer whose data contains personally identifiable information."

  use Chronicle.Events.EventType, id: "customer-registered"

  defstruct [:customer_id, :email, :full_name, :phone_number]

  pii :email, "Customer email address"
  pii :full_name, "Customer full name"
  pii :phone_number, "Customer phone number"

  unique_event_type()
end
