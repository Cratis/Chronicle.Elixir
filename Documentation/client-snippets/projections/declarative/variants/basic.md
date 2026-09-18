```elixir
defmodule MyApp.Projections.DecVariantBacklogItemProjection do
  use Chronicle.Projections.Projection, model: MyApp.ReadModels.DecVariantBacklogItem

  alias MyApp.Events.DecVariantIssueCreated
  alias MyApp.ReadModels.DecVariantWorkItem

  variant_of DecVariantWorkItem, key: :id
  enters_on DecVariantIssueCreated

  from DecVariantIssueCreated,
    set: [id: :event_source_id, title: :title]
end

defmodule MyApp.Projections.DecVariantPullRequestItemProjection do
  use Chronicle.Projections.Projection, model: MyApp.ReadModels.DecVariantPullRequestItem

  alias MyApp.Events.DecVariantPullRequestCreated
  alias MyApp.ReadModels.DecVariantWorkItem

  variant_of DecVariantWorkItem, key: :id
  enters_on DecVariantPullRequestCreated

  from DecVariantPullRequestCreated,
    set: [id: :event_source_id, pull_request_url: :pull_request_url]
end
```
