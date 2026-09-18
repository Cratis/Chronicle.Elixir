```elixir
defmodule MyApp.Events.MbVariantUpdatingPullRequestCreated do
  use Chronicle.Events.EventType, id: "mb-variant-updating-pull-request-created-v1"

  defstruct [:pull_request_url]
end

defmodule MyApp.Events.MbVariantUpdatingBuildCompleted do
  use Chronicle.Events.EventType, id: "mb-variant-updating-build-completed-v1"

  defstruct [:build_status]
end

defmodule MyApp.ReadModels.MbVariantUpdatingWorkItem do
end

# build_status is mapped from MbVariantUpdatingBuildCompleted - an event that is NOT this
# variant's entering event, so it is automatically reclassified into an update-only join. It can
# bring an already-active instance up to date, but it can never create one on its own.
defmodule MyApp.ReadModels.MbVariantUpdatingPullRequestItem do
  use Chronicle.ReadModels.ReadModel

  alias MyApp.Events.{MbVariantUpdatingPullRequestCreated, MbVariantUpdatingBuildCompleted}
  alias MyApp.ReadModels.MbVariantUpdatingWorkItem

  defstruct [:id, :pull_request_url, :build_status]

  variant_of MbVariantUpdatingWorkItem, key: :id
  enters_on MbVariantUpdatingPullRequestCreated

  from MbVariantUpdatingPullRequestCreated,
    set: [id: :event_source_id, pull_request_url: :pull_request_url]

  from MbVariantUpdatingBuildCompleted,
    set: [build_status: :build_status]
end
```
