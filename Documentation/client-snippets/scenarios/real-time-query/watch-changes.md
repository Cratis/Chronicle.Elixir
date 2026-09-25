```elixir
defmodule MyApp.ScenariosQueryBookWatcher do
  alias MyApp.ReadModels.ScenariosQueryBook

  def watch do
    Chronicle.ReadModels.watch(ScenariosQueryBook)
  end

  def handle_message({:chronicle_read_model_changed, ScenariosQueryBook, changeset}) do
    if not changeset.removed and changeset.read_model do
      IO.puts("#{changeset.model_key}: on loan = #{changeset.read_model.on_loan}")
    end
  end

  def stop(watcher), do: Chronicle.ReadModels.unwatch(watcher)
end
```
