```elixir
defmodule MyApp.Events.DecVariantUpdatingPullRequestCreated do
  use Chronicle.Events.EventType, id: "dec-variant-updating-pull-request-created-v1"

  defstruct [:pull_request_url]
end

defmodule MyApp.Events.DecVariantUpdatingBuildCompleted do
  use Chronicle.Events.EventType, id: "dec-variant-updating-build-completed-v1"

  defstruct [:build_status]
end

defmodule MyApp.ReadModels.DecVariantUpdatingWorkItem do
end

defmodule MyApp.ReadModels.DecVariantUpdatingPullRequestItem do
  use Chronicle.ReadModels.ReadModel

  defstruct [:id, :pull_request_url, :build_status]
end

# `from DecVariantUpdatingBuildCompleted` is declared exactly like an ordinary multi-event
# projection. Because that event is NOT the one named with enters_on, it is automatically
# reclassified into an update-only join on the variant's own key when the definition is built -
# it can bring an already-active instance up to date, but it can never create one on its own.
defmodule MyApp.Projections.DecVariantUpdatingPullRequestItemProjection do
  use Chronicle.Projections.Projection, model: MyApp.ReadModels.DecVariantUpdatingPullRequestItem

  alias MyApp.Events.{DecVariantUpdatingPullRequestCreated, DecVariantUpdatingBuildCompleted}
  alias MyApp.ReadModels.DecVariantUpdatingWorkItem

  variant_of DecVariantUpdatingWorkItem, key: :id
  enters_on DecVariantUpdatingPullRequestCreated

  from DecVariantUpdatingPullRequestCreated,
    set: [id: :event_source_id, pull_request_url: :pull_request_url]

  from DecVariantUpdatingBuildCompleted,
    set: [build_status: :build_status]
end
```
