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

  `event_source` (a `Chronicle.EventSources.EventSource` module or name) and
  `event_stream` route this event through a registered definition, overriding any
  batch-level `:event_source`/`:event_stream` option. An explicit `concurrency_scope`
  always wins over the definition's concurrency dimensions. `routing` is resolved
  internally and not meant to be set.

  Rich batches carry routing, tags, subject, and occurred time per event. Their
  causation and identity remain batch-level: explicit batch causation wins,
  and the first resolved entry identity wins over the batch identity option.
  Transaction commits use the first entry's causation and the same resolved-entry
  identity precedence.

  ## Imported events

  An import (`Chronicle.Imports`) keeps everything the source says about an event, so an
  entry also carries:

    * `:correlation_id` — the correlation id the event was originally written under
      (`Chronicle.Correlation.CorrelationId` or a UUID string)
    * `:identity` — who caused the event (sent as `CausedBy`)
    * `:causation` — the original causation chain
    * `:generation` — the event type generation the event was written in, when it differs
      from the generation its module declares
    * `:source_sequence_number` — the event's sequence number in the system it is imported
      from, kept as lineage; the event still gets a new sequence number
    * `:idempotency_key` — a key, typically the source system's event id, that makes
      importing the same event twice report it as already appended
    * `:named_tags` — a map of tag name to value

  Ordinary appends honor `:generation` for the event type they send. They take their
  correlation id from the `:correlation_id` option rather than from the entry, and do not
  use `:source_sequence_number`, `:idempotency_key` or `:named_tags`.
  """

  alias Chronicle.Auditing.CausationEntry
  alias Chronicle.Correlation.CorrelationId
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
    :event_source,
    :event_stream,
    :routing,
    :prepared,
    :correlation_id,
    :generation,
    :source_sequence_number,
    :idempotency_key,
    :named_tags,
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
          event_source: module() | String.t() | nil,
          event_stream: String.t() | nil,
          routing: Chronicle.EventSources.Routing.t() | nil,
          prepared: %{event_type: struct(), content: String.t()} | nil,
          correlation_id: CorrelationId.t() | String.t() | nil,
          generation: pos_integer() | nil,
          source_sequence_number: non_neg_integer() | nil,
          idempotency_key: String.t() | nil,
          named_tags: %{optional(String.t()) => String.t()} | nil,
          causation: [CausationEntry.t()],
          identity: Identity.t() | nil
        }
end
