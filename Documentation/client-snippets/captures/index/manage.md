```elixir
defmodule MyApp.CapturesIndexManage do
  alias MyApp.Captures.CapturesIndexInvoiceCapture

  def register_and_start do
    {:ok, _capture} = Cratis.Chronicle.Captures.register(CapturesIndexInvoiceCapture)
    :ok = Cratis.Chronicle.Captures.start(CapturesIndexInvoiceCapture)
  end

  def list_captures do
    Cratis.Chronicle.Captures.list()
  end

  def validate_declaration do
    Cratis.Chronicle.Captures.validate(CapturesIndexInvoiceCapture)
  end

  def recent_captured_events do
    Cratis.Chronicle.Captures.captured_events("InvoiceCapture", max_events: 50)
  end

  def stop_and_delete do
    :ok = Cratis.Chronicle.Captures.stop(CapturesIndexInvoiceCapture)
    :ok = Cratis.Chronicle.Captures.delete(CapturesIndexInvoiceCapture)
  end
end
```
