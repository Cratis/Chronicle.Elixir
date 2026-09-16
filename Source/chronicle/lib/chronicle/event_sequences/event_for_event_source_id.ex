# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.EventSequences.EventForEventSourceId do
  @moduledoc """
  Represents an event buffered for a specific event source within an event sequence.

  Omitted, `nil`, or empty routing values defer to the kernel's source type,
  stream type, and stream id defaults. Explicit nonempty routing is preserved.
  `occurred: nil` leaves timestamp assignment to the kernel; an explicit
  `DateTime` is preserved, including when the event is buffered in a transaction.

  Concurrency scopes are independent filters, not routing defaults. A missing
  scope sends no explicit constraint for this source; a scope, including `none()`,
  is sent unchanged. For repeated sources, the first declared scope wins.

  Rich batches carry routing, tags, subject, and occurred time per event. Their
  causation and identity remain batch-level: explicit batch causation wins,
  and the first resolved entry identity wins over the batch identity option.
  Transaction commits use the first entry's causation and the same resolved-entry
  identity precedence.
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
