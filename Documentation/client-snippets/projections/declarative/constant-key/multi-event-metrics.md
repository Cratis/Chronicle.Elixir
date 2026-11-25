```elixir title="Multiple events sharing a constant key"
defmodule MyApp.Events.DecConstantKeyPageViewed do
  use Cratis.Chronicle.Events.EventType, id: "dec-constant-key-page-viewed"

  defstruct [:page_url]
end

defmodule MyApp.Events.DecConstantKeyButtonClicked do
  use Cratis.Chronicle.Events.EventType, id: "dec-constant-key-button-clicked"

  defstruct [:button_id]
end

defmodule MyApp.Events.DecConstantKeyFormSubmitted do
  use Cratis.Chronicle.Events.EventType, id: "dec-constant-key-form-submitted"

  defstruct [:form_id]
end

defmodule MyApp.ReadModels.DecConstantKeyEngagementMetrics do
  use Cratis.Chronicle.ReadModels.ReadModel

  defstruct page_views: 0, button_clicks: 0, form_submissions: 0
end

defmodule MyApp.Projections.DecConstantKeyEngagementMetricsProjection do
  use Cratis.Chronicle.Projections.Projection, model: MyApp.ReadModels.DecConstantKeyEngagementMetrics

  alias MyApp.Events.{DecConstantKeyPageViewed, DecConstantKeyButtonClicked, DecConstantKeyFormSubmitted}

  from DecConstantKeyPageViewed,
    key: "metrics",
    count: :page_views

  from DecConstantKeyButtonClicked,
    key: "metrics",
    count: :button_clicks

  from DecConstantKeyFormSubmitted,
    key: "metrics",
    count: :form_submissions
end
```
