# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.ReadModels.DecisionReadRefused do
  @moduledoc """
  Raised when a read model's shape, or the requested stream scope, is not safe to guard a
  decision with.

  `:reason` mirrors the C# client's `DecisionReadRefusalReason`:

    * `:reducer` — the model is produced by an actively-observed reducer. Only a **passive**
      reducer (`use Chronicle.Reducers.Reducer, active: false`) can back a decision read.
    * `:join` — the projection declares `join/2` or `removed_with_join/2`. A joined read can
      change from an event outside the guarded event source, which the guard cannot express.
    * `:hierarchy` — the projection declares `children/2`. Nested/child collections are not
      representable as a single concurrency scope.
    * `:not_event_log` — the read model does not project from `"event-log"` (an `:event_sequence`
      override), or is not a recognized read model/reducer at all.
    * `:open_ended_event_types` — the projection declares `from_every/1`: it would have to guard
      against every event type ever appended, which Chronicle's `ConcurrencyScope` cannot express.
    * `:no_event_types` — the admitted shape resolves to no event types at all.
    * `:not_event_source_keyed` — a `from`/`removed_with` clause declares a `:key` other than the
      default `"$eventSourceId"` (a composite key, an event-context key, or similar).
    * `:unsupported_event_type_id` — one of the model's event type ids contains a comma, which
      cannot be told apart from an id list on the wire.
    * `:all_streams_not_supported` — a stream-scoped read was asked for the default stream (an
      empty or `"All"` event stream type) instead of a specific one.
    * `:stream_scope_not_supported` — the kernel reported the read model instance as not
      stream-scoped (`StreamScoped: false`), so a stream-scoped guard cannot be built from it.
    * `:fold_incomplete` — after 3 attempts, the read model still had not caught up to events
      already visible for its key/types; the read could not be made deterministic.
  """

  defexception [:reason, :read_model]

  @type reason ::
          :reducer
          | :join
          | :hierarchy
          | :not_event_log
          | :open_ended_event_types
          | :no_event_types
          | :not_event_source_keyed
          | :unsupported_event_type_id
          | :all_streams_not_supported
          | :stream_scope_not_supported
          | :fold_incomplete

  @impl true
  def message(%__MODULE__{reason: reason, read_model: read_model}) do
    "Decision read on #{inspect(read_model)} was refused: #{reason}"
  end
end
