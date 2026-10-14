```elixir
defmodule MyApp.Events.DecRwjDeveloperOnboarded do
  use Chronicle.Events.EventType, id: "dec-rwj-developer-onboarded"

  defstruct [:name, skills: []]
end

defmodule MyApp.Events.DecRwjDeveloperAssignedToProject do
  use Chronicle.Events.EventType, id: "dec-rwj-developer-assigned-to-project"

  defstruct [:developer_id, :project_id, :role, allocation: 0]
end

defmodule MyApp.Events.DecRwjDeveloperUnassignedFromProject do
  use Chronicle.Events.EventType, id: "dec-rwj-developer-unassigned-from-project"

  defstruct [:developer_id, :project_id]
end

defmodule MyApp.Events.DecRwjProjectInitiated do
  use Chronicle.Events.EventType, id: "dec-rwj-project-initiated"

  defstruct [:project_name, :priority, :deadline]
end

defmodule MyApp.Events.DecRwjProjectCancelled do
  use Chronicle.Events.EventType, id: "dec-rwj-project-cancelled"

  defstruct []
end

defmodule MyApp.Events.DecRwjProjectCompleted do
  use Chronicle.Events.EventType, id: "dec-rwj-project-completed"

  defstruct []
end

defmodule MyApp.ReadModels.DecRwjProjectAssignment do
  defstruct project_id: nil,
            project_name: nil,
            priority: nil,
            deadline: nil,
            assigned_at: nil,
            role: nil,
            allocation: 0
end

defmodule MyApp.ReadModels.DecRwjDeveloperProfile do
  use Chronicle.ReadModels.ReadModel,
    types: [current_projects: {:list, MyApp.ReadModels.DecRwjProjectAssignment}]

  defstruct developer_id: nil, name: nil, onboarded_at: nil, current_projects: []
end

defmodule MyApp.Projections.DecRwjDeveloperProjectsProjection do
  use Chronicle.Projections.Projection, model: MyApp.ReadModels.DecRwjDeveloperProfile

  alias MyApp.Events.{
    DecRwjDeveloperAssignedToProject,
    DecRwjDeveloperOnboarded,
    DecRwjDeveloperUnassignedFromProject,
    DecRwjProjectCancelled,
    DecRwjProjectCompleted,
    DecRwjProjectInitiated
  }

  from DecRwjDeveloperOnboarded, set: [developer_id: :event_source_id, onboarded_at: :occurred]

  children :current_projects, identified_by: :project_id do
    from DecRwjDeveloperAssignedToProject,
      parent_key: :developer_id,
      key: :project_id,
      set: [project_id: :project_id, role: :role, allocation: :allocation, assigned_at: :occurred]

    join DecRwjProjectInitiated,
      set: [project_name: :project_name, priority: :priority, deadline: :deadline]

    removed_with DecRwjDeveloperUnassignedFromProject, parent_key: :developer_id, key: :project_id

    removed_with_join DecRwjProjectCancelled
    removed_with_join DecRwjProjectCompleted
  end
end
```
