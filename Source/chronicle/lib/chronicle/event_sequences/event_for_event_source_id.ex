# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.EventSequences.EventForEventSourceId do
  @moduledoc """
  Represents an event buffered for a specific event source within an event sequence.
  """

  alias Chronicle.Auditing.CausationEntry
  alias Chronicle.Identity
  alias Chronicle.Events.ConcurrencyScope

  @enforce_keys [:event_source_id, :event]
  defstruct [
    :event_source_id,
    :event,
    :event_source_type,
    :event_stream_type,
    :event_stream_id,
    :tags,
    :subject,
    :occurred,
    :concurrency_scope,
    causation: [],
    identity: nil
  ]

  @type t :: %__MODULE__{
          event_source_id: String.t(),
          event: struct(),
          event_source_type: String.t() | nil,
          event_stream_type: String.t() | nil,
          event_stream_id: String.t() | nil,
          tags: [String.t()] | nil,
          subject: String.t() | nil,
          occurred: DateTime.t() | nil,
          concurrency_scope: ConcurrencyScope.t() | keyword() | nil,
          causation: [CausationEntry.t()],
          identity: Identity.t() | nil
        }
end
