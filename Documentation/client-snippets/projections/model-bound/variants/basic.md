```elixir
defmodule MyApp.Events.MbVariantIssueCreated do
  use Chronicle.Events.EventType, id: "mb-variant-issue-created-v1"

  defstruct [:title]
end

defmodule MyApp.Events.MbVariantPullRequestCreated do
  use Chronicle.Events.EventType, id: "mb-variant-pull-request-created-v1"

  defstruct [:pull_request_url]
end

# Anchors the logical identity shared by every variant. It does not need to be a read model
# itself, and it does not need a common shape with any of the variants.
defmodule MyApp.ReadModels.MbVariantWorkItem do
end

defmodule MyApp.ReadModels.MbVariantBacklogItem do
  use Chronicle.ReadModels.ReadModel

  alias MyApp.Events.MbVariantIssueCreated
  alias MyApp.ReadModels.MbVariantWorkItem

  defstruct [:id, :title]

  variant_of MbVariantWorkItem, key: :id
  enters_on MbVariantIssueCreated

  from MbVariantIssueCreated,
    set: [id: :event_source_id, title: :title]
end

defmodule MyApp.ReadModels.MbVariantPullRequestItem do
  use Chronicle.ReadModels.ReadModel

  alias MyApp.Events.MbVariantPullRequestCreated
  alias MyApp.ReadModels.MbVariantWorkItem

  defstruct [:id, :pull_request_url]

  variant_of MbVariantWorkItem, key: :id
  enters_on MbVariantPullRequestCreated

  from MbVariantPullRequestCreated,
    set: [id: :event_source_id, pull_request_url: :pull_request_url]
end
```
