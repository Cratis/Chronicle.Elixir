```elixir title="Model-bound children ordering"
defmodule MyApp.Events.MbOrderingCommentPosted do
  use Chronicle.Events.EventType, id: "mb-ordering-comment-posted"

  defstruct comment_id: "", text: ""
end

defmodule MyApp.Events.MbOrderingTaskAdded do
  use Chronicle.Events.EventType, id: "mb-ordering-task-added"

  defstruct task_id: "", title: "", priority: 0
end

defmodule MyApp.ReadModels.MbOrderingComment do
  defstruct comment_id: "", text: ""
end

defmodule MyApp.ReadModels.MbOrderingTask do
  defstruct task_id: "", title: "", priority: 0
end

defmodule MyApp.ReadModels.MbOrderingBoard do
  use Chronicle.ReadModels.ReadModel,
    types: [
      comments: {:list, MyApp.ReadModels.MbOrderingComment},
      tasks: {:list, MyApp.ReadModels.MbOrderingTask}
    ]

  alias MyApp.Events.{MbOrderingCommentPosted, MbOrderingTaskAdded}

  defstruct comments: [], tasks: []

  children :comments,
    from: MbOrderingCommentPosted,
    identified_by: :comment_id,
    key: :comment_id,
    prepend: true

  children :tasks,
    from: MbOrderingTaskAdded,
    identified_by: :task_id,
    key: :task_id,
    order_by: [desc: :priority]
end
```
