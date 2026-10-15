```elixir
defmodule MyApp.Events.EditingConflictProjectRenamed do
  use Chronicle.Events.EventType, id: "editing-conflict-project-renamed"

  defstruct [:name]
end

defmodule MyApp.EditingConflictRenameProject do
  alias Chronicle.EventSequences.EventLog
  alias Chronicle.Events.ConcurrencyScope
  alias MyApp.Events.EditingConflictProjectRenamed

  # Capture this BEFORE you load the form data, then return it with the form. Load the data from the
  # event log or a passive read model (a fresh fold), never from a materialized read model.
  def revision(project_id) do
    case EventLog.has_events_for?(project_id) do
      # A project with no events has no tail: "no matching event had been appended when the user
      # loaded the form".
      {:ok, false} -> {:ok, :none}
      {:ok, true} -> EventLog.get_tail_sequence_number(project_id)
      {:error, reason} -> {:error, reason}
    end
  end

  def rename(project_id, name, revision_the_user_saw) do
    # Reject if anyone renamed the project after the revision the user saw.
    options = [event_types: [EditingConflictProjectRenamed]]

    scope =
      case revision_the_user_saw do
        :none -> ConcurrencyScope.expecting_no_matching_event([event_source_id: true] ++ options)
        sequence_number -> ConcurrencyScope.for_event_source(sequence_number, options)
      end

    EventLog.append(project_id, %EditingConflictProjectRenamed{name: name}, concurrency_scope: scope) ==
      :ok
  end
end
```
