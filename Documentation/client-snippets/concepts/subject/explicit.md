```elixir
defmodule MyApp.Events.SubjectShippingAddressChanged do
  use Chronicle.Events.EventType, id: "subject-shipping-address-changed"

  defstruct [:street]
end

defmodule MyApp.SubjectShippingService do
  alias MyApp.Events.SubjectShippingAddressChanged

  def change_address(order_id, customer_id, street) do
    Chronicle.append(order_id, %SubjectShippingAddressChanged{street: street},
      subject: customer_id
    )
  end
end
```
