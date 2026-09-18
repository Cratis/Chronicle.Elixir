```elixir
defmodule MyApp.Events.DecVariantIssueCreated do
  use Chronicle.Events.EventType, id: "dec-variant-issue-created-v1"

  defstruct [:title]
end

defmodule MyApp.Events.DecVariantPullRequestCreated do
  use Chronicle.Events.EventType, id: "dec-variant-pull-request-created-v1"

  defstruct [:pull_request_url]
end
```
