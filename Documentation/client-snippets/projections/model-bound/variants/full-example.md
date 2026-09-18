```elixir
defmodule MyApp.Events.MbVariantFullIssueCreated do
  use Chronicle.Events.EventType, id: "mb-variant-full-issue-created-v1"

  defstruct [:title]
end

defmodule MyApp.Events.MbVariantFullPullRequestCreated do
  use Chronicle.Events.EventType, id: "mb-variant-full-pull-request-created-v1"

  defstruct [:pull_request_url]
end

defmodule MyApp.Events.MbVariantFullBuildCompleted do
  use Chronicle.Events.EventType, id: "mb-variant-full-build-completed-v1"

  defstruct [:build_status]
end

defmodule MyApp.Events.MbVariantFullTitleChanged do
  use Chronicle.Events.EventType, id: "mb-variant-full-title-changed-v1"

  defstruct [:title]
end

# Anchors the logical identity shared by MbVariantFullBacklogItem and
# MbVariantFullPullRequestItem. Deliberately not a read model itself.
defmodule MyApp.ReadModels.MbVariantFullWorkItem do
end

# The variant an entity is in before a pull request exists for it.
defmodule MyApp.ReadModels.MbVariantFullBacklogItem do
  use Chronicle.ReadModels.ReadModel

  alias MyApp.Events.MbVariantFullIssueCreated
  alias MyApp.ReadModels.MbVariantFullWorkItem

  defstruct [:id, :title]

  variant_of MbVariantFullWorkItem, key: :id
  enters_on MbVariantFullIssueCreated

  from MbVariantFullIssueCreated,
    set: [id: :event_source_id]
end

# The variant an entity enters once a pull request is created for it. build_status is mapped
# from MbVariantFullBuildCompleted - an event that is NOT this variant's entering event, so it
# becomes an update-only join and can never create the row on its own.
defmodule MyApp.ReadModels.MbVariantFullPullRequestItem do
  use Chronicle.ReadModels.ReadModel

  alias MyApp.Events.{MbVariantFullPullRequestCreated, MbVariantFullBuildCompleted}
  alias MyApp.ReadModels.MbVariantFullWorkItem

  defstruct [:id, :title, :pull_request_url, :build_status]

  variant_of MbVariantFullWorkItem, key: :id
  enters_on MbVariantFullPullRequestCreated

  from MbVariantFullPullRequestCreated,
    set: [id: :event_source_id, pull_request_url: :pull_request_url]

  from MbVariantFullBuildCompleted,
    set: [build_status: :build_status]
end

# Declares a mapping every variant of MbVariantFullWorkItem shares.
defmodule MyApp.Projections.MbVariantFullSharedHandlers do
  use Chronicle.Projections.GlobalHandler, identity: MyApp.ReadModels.MbVariantFullWorkItem

  alias MyApp.Events.MbVariantFullTitleChanged

  from MbVariantFullTitleChanged,
    set: [title: :title]
end
```
