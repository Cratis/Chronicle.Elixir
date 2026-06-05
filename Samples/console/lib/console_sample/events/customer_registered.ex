# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule ConsoleSample.Events.CustomerRegistered do
  @moduledoc "Registers a customer whose data contains personally identifiable information."

  use Chronicle.EventType, id: "customer-registered"

  defstruct [:customer_id, :email, :full_name, :phone_number]

  unique_event_type()
end
