```elixir
defmodule MyApp.ScenariosQueryLiveBookPage do
  alias MyApp.ReadModels.ScenariosQueryBook

  # The calling process receives the page now, and again every time it changes.
  def subscribe do
    Chronicle.ReadModels.observe(ScenariosQueryBook, page_size: 50)
  end

  def handle_message({:chronicle_read_model_instances, ScenariosQueryBook, result}) do
    result.instances
  end

  # The stream failed and the observation ended; call subscribe/0 again to resume.
  def handle_message({:chronicle_read_model_observe_error, ScenariosQueryBook, reason}) do
    {:error, reason}
  end

  def unsubscribe(observer), do: Chronicle.ReadModels.unobserve(observer)
end
```
