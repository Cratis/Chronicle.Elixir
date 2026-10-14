```elixir
defmodule MyApp.Events.CapturesIndexCustomerChanged do
  use Chronicle.Events.EventType, id: "CustomerChanged"

  defstruct [:first_name, :last_name]
end

defmodule MyApp.Events.CapturesIndexBillingAddressChanged do
  use Chronicle.Events.EventType, id: "BillingAddressChanged"

  defstruct [:street]
end

defmodule MyApp.Events.CapturesIndexItemAdded do
  use Chronicle.Events.EventType, id: "ItemAdded"

  defstruct [:line_number]
end

defmodule MyApp.Captures.CapturesIndexCustomerCapture do
  use Chronicle.Captures.Capture, name: "CustomerCapture"

  alias MyApp.Events.{
    CapturesIndexBillingAddressChanged,
    CapturesIndexCustomerChanged,
    CapturesIndexItemAdded
  }

  api_source("CustomersApi", poll: "5m")

  key("customerId")

  map do
    rename(:full_name, :fornavn)
    translate(:status, :status, [{"aktiv", "active"}, {"inaktiv", "inactive"}])
  end

  append CapturesIndexCustomerChanged, when: {:any, ["firstName", "lastName"]} do
    set(:first_name, "$.firstName")
  end

  nested :billing_address do
    map do
      rename(:street, :"fakturaAdresse.gate")
    end

    append CapturesIndexBillingAddressChanged, when: "street" do
      set(:street, "$.street")
    end
  end

  children :line_items, identified_by: :line_number do
    append CapturesIndexItemAdded, when: :added do
      set(:line_number, "$.lineNumber")
    end
  end
end
```
