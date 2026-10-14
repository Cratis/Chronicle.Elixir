```elixir
defmodule MyApp.ReadModels.TaggingUserAnalytics do
  use Chronicle.ReadModels.ReadModel

  defstruct id: nil, login_count: 0, critical_login_count: 0
end

defmodule MyApp.Reducers.TaggingUserAnalyticsReducer do
  use Chronicle.Reducers.Reducer, model: MyApp.ReadModels.TaggingUserAnalytics

  alias MyApp.Events.TaggingUserLoggedIn
  alias MyApp.ReadModels.TaggingUserAnalytics

  @handles TaggingUserLoggedIn

  @impl true
  def reduce(%TaggingUserLoggedIn{}, model, context) do
    analytics = model || %TaggingUserAnalytics{id: context.event_source_id}

    # Access tags from the event context
    critical? = "critical" in context.tags

    %{
      analytics
      | login_count: analytics.login_count + 1,
        critical_login_count: analytics.critical_login_count + if(critical?, do: 1, else: 0)
    }
  end
end
```
