```elixir
defmodule MyApp.Events.MbVariantSharedIssueCreated do
  use Chronicle.Events.EventType, id: "mb-variant-shared-issue-created-v1"

  defstruct [:title]
end

defmodule MyApp.Events.MbVariantSharedPullRequestCreated do
  use Chronicle.Events.EventType, id: "mb-variant-shared-pull-request-created-v1"

  defstruct [:pull_request_url]
end

defmodule MyApp.Events.MbVariantSharedTitleChanged do
  use Chronicle.Events.EventType, id: "mb-variant-shared-title-changed-v1"

  defstruct [:title]
end

defmodule MyApp.ReadModels.MbVariantSharedWorkItem do
end

defmodule MyApp.ReadModels.MbVariantSharedBacklogItem do
  use Chronicle.ReadModels.ReadModel

  alias MyApp.Events.MbVariantSharedIssueCreated
  alias MyApp.ReadModels.MbVariantSharedWorkItem

  defstruct [:id, :title]

  variant_of MbVariantSharedWorkItem, key: :id
  enters_on MbVariantSharedIssueCreated

  from MbVariantSharedIssueCreated,
    set: [id: :event_source_id]
end

defmodule MyApp.ReadModels.MbVariantSharedPullRequestItem do
  use Chronicle.ReadModels.ReadModel

  alias MyApp.Events.MbVariantSharedPullRequestCreated
  alias MyApp.ReadModels.MbVariantSharedWorkItem

  defstruct [:id, :title, :pull_request_url]

  variant_of MbVariantSharedWorkItem, key: :id
  enters_on MbVariantSharedPullRequestCreated

  from MbVariantSharedPullRequestCreated,
    set: [id: :event_source_id, pull_request_url: :pull_request_url]
end

# Declares a mapping every variant of MbVariantSharedWorkItem shares. Every variant must have a
# title member - one that does not is a declaration error, not a silently skipped mapping. Never
# registered as a projection on its own.
defmodule MyApp.Projections.MbVariantSharedHandlers do
  use Chronicle.Projections.GlobalHandler, identity: MyApp.ReadModels.MbVariantSharedWorkItem

  alias MyApp.Events.MbVariantSharedTitleChanged

  from MbVariantSharedTitleChanged,
    set: [title: :title]
end
```
