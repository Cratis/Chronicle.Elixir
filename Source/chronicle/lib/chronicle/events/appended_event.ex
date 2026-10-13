# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Events.AppendedEvent do
  @moduledoc """
  An event read back from an event sequence, decoded into the event struct it was appended as.

  Returned by `Chronicle.EventSequences.EventLog.get_for_event_source/2` and
  `get_from_sequence_number/2` when called with `decode: true`.

    * `:event` — the event struct for a registered event type, or `nil` when the event type is
      not registered with this client (or the event was redacted); the decoded payload is then
      still available in `:raw`.
    * `:raw` — the event content as a map with the wire (camelCase) keys.
    * `:context` — the `Chronicle.Events.EventContext`.
    * `:type` — `%{id: String.t(), generation: non_neg_integer()}`.
    * `:redacted?` / `:redaction` — set for events that were redacted for compliance; the
      redaction carries the `:reason` and the `:original_event_type` id.
  """

  alias Chronicle.Events.EventContext
  alias Chronicle.Serialization

  defstruct [:event, :context, :type, raw: %{}, redacted?: false, redaction: nil]

  @type t :: %__MODULE__{
          event: struct() | nil,
          raw: map(),
          context: EventContext.t(),
          type: %{id: String.t(), generation: non_neg_integer()} | nil,
          redacted?: boolean(),
          redaction: %{reason: String.t(), original_event_type: String.t()} | nil
        }

  @redaction_type_id "EventRedacted"

  @doc """
  Decodes a wire `AppendedEvent`, resolving the event struct from `event_types`
  (a list of event type modules).
  """
  @spec from_wire(map(), [module()]) :: t()
  def from_wire(appended, event_types) do
    context = EventContext.from_wire(Map.get(appended, :Context, %{}))
    raw = decode_content(Map.get(appended, :Content, ""))
    type = context.event_type

    if type && String.downcase(type.id) == String.downcase(@redaction_type_id) do
      %__MODULE__{
        context: context,
        type: type,
        raw: raw,
        redacted?: true,
        redaction: %{
          reason: Map.get(raw, "reason", ""),
          original_event_type: Map.get(raw, "originalEventType", "")
        }
      }
    else
      %__MODULE__{
        context: context,
        type: type,
        raw: raw,
        event: resolve(type, raw, event_types)
      }
    end
  end

  defp resolve(nil, _raw, _event_types), do: nil

  defp resolve(%{id: id, generation: generation}, raw, event_types) do
    module =
      Enum.find(event_types, fn module ->
        module.__chronicle_event_type__(:id) == id and
          module.__chronicle_event_type__(:generation) == generation
      end) || Enum.find(event_types, &(&1.__chronicle_event_type__(:id) == id))

    if module, do: Serialization.decode(module, raw, :camel)
  end

  defp decode_content(content) when is_binary(content) and content != "" do
    case Jason.decode(content) do
      {:ok, map} when is_map(map) -> map
      _ -> %{}
    end
  end

  defp decode_content(_), do: %{}
end
