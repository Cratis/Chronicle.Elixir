```elixir
defmodule MyApp.Events.DecVariantFullIssueCreated do
  use Chronicle.Events.EventType, id: "dec-variant-full-issue-created-v1"

  defstruct [:title]
end

defmodule MyApp.Events.DecVariantFullPullRequestCreated do
  use Chronicle.Events.EventType, id: "dec-variant-full-pull-request-created-v1"

  defstruct [:pull_request_url]
end

defmodule MyApp.Events.DecVariantFullBuildCompleted do
  use Chronicle.Events.EventType, id: "dec-variant-full-build-completed-v1"

  defstruct [:build_status]
end

# Anchors the logical identity shared by DecVariantFullBacklogItem and
# DecVariantFullPullRequestItem. Deliberately not a read model itself.
defmodule MyApp.ReadModels.DecVariantFullWorkItem do
end

defmodule MyApp.ReadModels.DecVariantFullBacklogItem do
  use Chronicle.ReadModels.ReadModel

  defstruct [:id, :title]
end

defmodule MyApp.ReadModels.DecVariantFullPullRequestItem do
  use Chronicle.ReadModels.ReadModel

  defstruct [:id, :pull_request_url, :build_status]
end

# The variant an entity is in before a pull request exists for it.
defmodule MyApp.Projections.DecVariantFullBacklogItemProjection do
  use Chronicle.Projections.Projection, model: MyApp.ReadModels.DecVariantFullBacklogItem

  alias MyApp.Events.DecVariantFullIssueCreated
  alias MyApp.ReadModels.DecVariantFullWorkItem

  variant_of DecVariantFullWorkItem, key: :id
  enters_on DecVariantFullIssueCreated

  from DecVariantFullIssueCreated,
    set: [id: :event_source_id, title: :title]
end

# The variant an entity enters once a pull request is created for it. build_status comes from
# DecVariantFullBuildCompleted - an event that is NOT this variant's entering event, so it is
# reclassified into an update-only join and can never create the row on its own.
defmodule MyApp.Projections.DecVariantFullPullRequestItemProjection do
  use Chronicle.Projections.Projection, model: MyApp.ReadModels.DecVariantFullPullRequestItem

  alias MyApp.Events.{DecVariantFullPullRequestCreated, DecVariantFullBuildCompleted}
  alias MyApp.ReadModels.DecVariantFullWorkItem

  variant_of DecVariantFullWorkItem, key: :id
  enters_on DecVariantFullPullRequestCreated

  from DecVariantFullPullRequestCreated,
    set: [id: :event_source_id, pull_request_url: :pull_request_url]

  from DecVariantFullBuildCompleted,
    set: [build_status: :build_status]
end
```
