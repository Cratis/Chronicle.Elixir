```elixir
defmodule MyApp.Events.MbChildrenSectionAdded do
  use Chronicle.Events.EventType, id: "mb-children-section-added"

  defstruct [:section_id, :section_name]
end

defmodule MyApp.Events.MbChildrenTaskAddedToSection do
  use Chronicle.Events.EventType, id: "mb-children-task-added-to-section"

  defstruct [:section_id, :task_id, :task_name]
end

defmodule MyApp.Events.MbChildrenTaskCompleted do
  use Chronicle.Events.EventType, id: "mb-children-task-completed"

  defstruct [:task_id]
end

defmodule MyApp.ReadModels.MbChildrenTask do
  defstruct task_id: nil, task_name: nil, completed: false
end

defmodule MyApp.ReadModels.MbChildrenSection do
  defstruct section_id: nil, section_name: nil, tasks: []
end

defmodule MyApp.ReadModels.MbChildrenBoard do
  use Chronicle.ReadModels.ReadModel,
    types: [
      sections: {:list, MyApp.ReadModels.MbChildrenSection},
      tasks: {:list, MyApp.ReadModels.MbChildrenTask}
    ]

  defstruct board_id: nil, sections: []

  children :sections, identified_by: :section_id do
    from MyApp.Events.MbChildrenSectionAdded,
      key: :section_id,
      set: [section_id: :section_id, section_name: :section_name]

    children :tasks, identified_by: :task_id do
      from MyApp.Events.MbChildrenTaskAddedToSection,
        key: :task_id,
        parent_key: :section_id,
        set: [task_id: :task_id, task_name: :task_name]

      from MyApp.Events.MbChildrenTaskCompleted,
        key: :task_id,
        set: [completed: true]
    end
  end
end
```
