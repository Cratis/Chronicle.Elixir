```elixir
defmodule MyApp.Events.TeamFormed do
  use Chronicle.Events.EventType, id: "graph-team-formed"
  defstruct team_id: "", name: ""
end

defmodule MyApp.Events.TeamMemberJoined do
  use Chronicle.Events.EventType, id: "graph-team-member-joined"
  defstruct team_id: ""
end

defmodule MyApp.Events.TeamMemberLeft do
  use Chronicle.Events.EventType, id: "graph-team-member-left"
  defstruct team_id: ""
end

defmodule MyApp.Graphs.Team do
  use Chronicle.Graphs.Node
  defstruct team_id: "", name: "", member_count: 0
end

defmodule MyApp.Graphs.Teams do
  use Chronicle.Graphs.Graph, id: "Teams"

  alias MyApp.Events.{TeamFormed, TeamMemberJoined, TeamMemberLeft}
  alias MyApp.Graphs.Team

  node Team, key: :team_id do
    from TeamFormed, key: :team_id
    from TeamMemberJoined, key: :team_id, increment: :member_count
    from TeamMemberLeft, key: :team_id, decrement: :member_count
  end
end
```
