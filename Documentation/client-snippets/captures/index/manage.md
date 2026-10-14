```elixir
defmodule MyApp.CapturesIndexManage do
  alias MyApp.Captures.CapturesIndexInvoiceCapture

  def register_and_start do
    {:ok, _capture} = Chronicle.Captures.register(CapturesIndexInvoiceCapture)
    :ok = Chronicle.Captures.start(CapturesIndexInvoiceCapture)
  end

  def list_captures do
    Chronicle.Captures.list()
  end

  def validate_declaration do
    Chronicle.Captures.validate(CapturesIndexInvoiceCapture)
  end

  def recent_captured_events do
    Chronicle.Captures.captured_events("InvoiceCapture", max_events: 50)
  end

  def stop_and_delete do
    :ok = Chronicle.Captures.stop(CapturesIndexInvoiceCapture)
    :ok = Chronicle.Captures.delete(CapturesIndexInvoiceCapture)
  end
end
```
