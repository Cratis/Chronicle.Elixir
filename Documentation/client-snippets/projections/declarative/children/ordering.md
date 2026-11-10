```elixir title="Ordering new children"
defmodule MyApp.Events.DecOrderingCommentPosted do
  use Chronicle.Events.EventType, id: "dec-ordering-comment-posted"

  defstruct comment_id: "", text: ""
end

defmodule MyApp.Events.DecOrderingTaskAdded do
  use Chronicle.Events.EventType, id: "dec-ordering-task-added"

  defstruct task_id: "", title: "", priority: 0
end

defmodule MyApp.ReadModels.DecOrderingComment do
  defstruct comment_id: "", text: ""
end

defmodule MyApp.ReadModels.DecOrderingTask do
  defstruct task_id: "", title: "", priority: 0
end

defmodule MyApp.ReadModels.DecOrderingBoard do
  use Chronicle.ReadModels.ReadModel,
    types: [
      comments: {:list, MyApp.ReadModels.DecOrderingComment},
      tasks: {:list, MyApp.ReadModels.DecOrderingTask}
    ]

  defstruct comments: [], tasks: []
end

defmodule MyApp.Projections.DecOrderingBoardProjection do
  use Chronicle.Projections.Projection, model: MyApp.ReadModels.DecOrderingBoard

  alias MyApp.Events.{DecOrderingCommentPosted, DecOrderingTaskAdded}

  # Newest comment first.
  children :comments, identified_by: :comment_id, prepend: true do
    from DecOrderingCommentPosted, key: :comment_id
  end

  # Highest priority first.
  children :tasks, identified_by: :task_id, order_by: [desc: :priority] do
    from DecOrderingTaskAdded, key: :task_id
  end
end
```
