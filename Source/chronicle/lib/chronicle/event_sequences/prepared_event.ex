# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.EventSequences.PreparedEvent do
  @moduledoc """
  An immutable, pre-serialized snapshot of an event, bound to the client, namespace and event
  sequence that prepared it.

  Create with `Chronicle.EventSequences.EventLog.prepare/2` and reuse with
  `Chronicle.EventSequences.EventLog.append_prepared/3` and
  `Chronicle.EventSequences.Streams.verify_content/3`. The content is serialized once, at
  preparation time; later changes to the original event struct have no effect on it. Appending
  a prepared event through a different client, namespace, or event sequence than the one that
  prepared it returns `{:error, :prepared_event_belongs_to_another_sequence}`.

  Mirrors the .NET client's `PreparedEvent` (`IEventSequence.Prepare`). Unlike .NET, single use
  is not enforced - a prepared event can be appended more than once, exactly like appending the
  same event struct twice.
  """

  @enforce_keys [:owner, :event, :event_type, :content]
  defstruct [:owner, :event, :event_type, :content]

  @type owner :: {client :: atom(), namespace :: String.t(), event_sequence_id :: String.t()}

  @type t :: %__MODULE__{
          owner: owner(),
          event: struct(),
          event_type: struct(),
          content: String.t()
        }
end
