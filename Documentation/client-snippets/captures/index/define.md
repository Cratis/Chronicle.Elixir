```elixir
defmodule MyApp.Events.CapturesIndexInvoiceStatusChanged do
  use Chronicle.Events.EventType, id: "InvoiceStatusChanged"

  defstruct [:status]
end

defmodule MyApp.Captures.CapturesIndexInvoiceCapture do
  use Chronicle.Captures.Capture, name: "InvoiceCapture"

  alias MyApp.Events.CapturesIndexInvoiceStatusChanged

  api_source("InvoicingApi", route: "/invoices", poll: "10m")

  key("id")

  append CapturesIndexInvoiceStatusChanged, when: "status" do
    set(:status, "$.status")
  end
end
```
