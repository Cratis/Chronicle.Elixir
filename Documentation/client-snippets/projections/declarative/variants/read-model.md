```elixir
# Anchors the logical identity shared by DecVariantBacklogItem and DecVariantPullRequestItem.
# Deliberately not a read model itself, and does not need a common shape with either variant.
defmodule MyApp.ReadModels.DecVariantWorkItem do
end

defmodule MyApp.ReadModels.DecVariantBacklogItem do
  use Chronicle.ReadModels.ReadModel

  defstruct [:id, :title]
end

defmodule MyApp.ReadModels.DecVariantPullRequestItem do
  use Chronicle.ReadModels.ReadModel

  defstruct [:id, :pull_request_url]
end
```
