# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule ConsoleSample.ReadModels.Customer do
  @moduledoc "Customer read model used for the compliance and PII demonstration."

  use Chronicle.ReadModel

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
end
