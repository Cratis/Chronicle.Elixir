# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule ConsoleSample.Events.CustomerAddressUpdated do
  @moduledoc "Updates a customer's address."

  use Chronicle.Events.EventType, id: "customer-address-updated"

  defstruct [:customer_id, :street_address, :city, :postal_code, :country]

  pii :street_address, "Customer street address"
  pii :city, "Customer city"
  pii :postal_code, "Customer postal code"
end
