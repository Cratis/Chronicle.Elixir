# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule ConsoleSample.ReadModels.Customer do
  @moduledoc "Customer read model used for the compliance and PII demonstration."

  use Chronicle.ReadModels.ReadModel

  defstruct id: "",
            full_name: "",
            email: "",
            phone_number: "",
            street_address: "",
            city: "",
            postal_code: "",
            country: "",
            customer_number: "",
            account_status: "active",
            total_orders: 0

  pii :full_name, "Customer full name"
  pii :email, "Customer email address"
  pii :phone_number, "Customer phone number"
  pii :street_address, "Customer street address"
  pii :city, "Customer city"
  pii :postal_code, "Customer postal code"
end
