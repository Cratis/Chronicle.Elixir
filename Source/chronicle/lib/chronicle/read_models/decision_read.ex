# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.ReadModels.DecisionRead do
  @moduledoc """
  A read model instance together with the concurrency guard that protects the decision made
  from it.

  Returned by `Chronicle.ReadModels.DecisionReads.get/3` and `get_detached/3` (and their stream
  variants). Never built directly - the struct's fields are internal shape, read by
  `Chronicle.Transactions.UnitOfWork.add_decision_read/2` and `Chronicle.EventSequences.EventLog`
  at commit time, not part of the public contract.
  """

  @enforce_keys [
    :read_model,
    :key,
    :event_source_id,
    :event_store,
    :namespace,
    :event_sequence_id,
    :scope,
    :event_types
  ]
  defstruct read_model: nil,
            key: nil,
            instance: nil,
            event_source_id: nil,
            event_store: nil,
            namespace: nil,
            event_sequence_id: "event-log",
            scope: nil,
            event_types: [],
            stream: nil

  @type stream_scope :: %{
          event_source_id: String.t(),
          event_stream_type: String.t(),
          event_stream_id: String.t(),
          event_source_type: String.t()
        }

  @type t :: %__MODULE__{
          read_model: module(),
          key: String.t(),
          instance: struct() | nil,
          event_source_id: String.t(),
          event_store: String.t(),
          namespace: String.t(),
          event_sequence_id: String.t(),
          scope: Chronicle.Events.ConcurrencyScope.t(),
          event_types: [module()],
          stream: stream_scope() | nil
        }
end
