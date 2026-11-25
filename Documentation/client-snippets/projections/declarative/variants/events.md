```elixir
defmodule MyApp.Events.DecVariantIssueCreated do
  use Cratis.Chronicle.Events.EventType, id: "dec-variant-issue-created-v1"

  defstruct [:title]
end

defmodule MyApp.Events.DecVariantPullRequestCreated do
  use Cratis.Chronicle.Events.EventType, id: "dec-variant-pull-request-created-v1"

  defstruct [:pull_request_url]
end
```
