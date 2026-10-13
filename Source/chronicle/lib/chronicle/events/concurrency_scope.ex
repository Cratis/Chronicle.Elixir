# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Events.ConcurrencyScope do
  @moduledoc """
  Represents a concurrency scope for Chronicle append operations.

  Concurrency scopes let you assert the expected tail sequence number before
  appending one or more events. You can optionally narrow the check to the
  current event source, stream, source type, and event types.

      alias Chronicle.Events.ConcurrencyScope

      scope =
        ConcurrencyScope.for_event_source(3,
          event_types: [MyApp.Events.FundsDeposited, MyApp.Events.FundsWithdrawn]
        )

      :ok = Chronicle.append_many("account-42", [...], concurrency_scope: scope)

  The `event_source_id` option is a boolean because the actual event source id
  comes from the `Chronicle.append/3` or `Chronicle.append_many/3` call.
  """

  @unset_sequence_number 18_446_744_073_709_551_615

  @enforce_keys [:sequence_number]
  defstruct sequence_number: @unset_sequence_number,
            event_source_id: false,
            event_stream_type: "",
            event_stream_id: "",
            event_source_type: "",
            event_types: [],
            expects_no_matching_event: false

  @type event_type_module :: module()

  @type option ::
          {:event_source_id, boolean()}
          | {:event_stream_type, String.t() | atom() | nil}
          | {:event_stream_id, String.t() | atom() | nil}
          | {:event_source_type, String.t() | atom() | nil}
          | {:event_types, [event_type_module()] | nil}
          | {:expects_no_matching_event, boolean()}

  @type t :: %__MODULE__{
          sequence_number: non_neg_integer(),
          event_source_id: boolean(),
          event_stream_type: String.t(),
          event_stream_id: String.t(),
          event_source_type: String.t(),
          event_types: [event_type_module()],
          expects_no_matching_event: boolean()
        }

  @doc """
  Creates a new concurrency scope.
  """
  @spec new(non_neg_integer(), [option()]) :: t()
  def new(sequence_number, opts \\ [])

  def new(sequence_number, opts)
      when is_integer(sequence_number) and sequence_number >= 0 do
    %__MODULE__{
      sequence_number: sequence_number,
      event_source_id: Keyword.get(opts, :event_source_id, false),
      event_stream_type: normalize_string(Keyword.get(opts, :event_stream_type, "")),
      event_stream_id: normalize_string(Keyword.get(opts, :event_stream_id, "")),
      event_source_type: normalize_string(Keyword.get(opts, :event_source_type, "")),
      event_types: normalize_event_types(Keyword.get(opts, :event_types, [])),
      expects_no_matching_event: Keyword.get(opts, :expects_no_matching_event, false)
    }
  end

  def new(sequence_number, _opts) do
    raise ArgumentError,
          "expected sequence_number to be a non-negative integer, got: #{inspect(sequence_number)}"
  end

  @doc """
  Creates a concurrency scope that includes the current append event source id.
  """
  @spec for_event_source(non_neg_integer(), [option()]) :: t()
  def for_event_source(sequence_number, opts \\ []) do
    new(sequence_number, Keyword.put(opts, :event_source_id, true))
  end

  @doc """
  Creates a scope asserting that **no** event matches the scope's dimensions yet - the guard for
  creation-only operations ("this event source must not have been registered already").

  Mirrors .NET's `ConcurrencyScopeBuilder.ExpectingNoMatchingEvent()`. It sends the kernel's explicit
  no-matching-event condition; leaving the sequence number unset is not a substitute, because
  that disables the check instead of asserting anything. The narrowing options are those of
  `new/2` - typically the event source and the event types that would make the append invalid:

      scope =
        ConcurrencyScope.expecting_no_matching_event(
          event_source_id: true,
          event_types: [MyApp.Events.UserRegistered]
        )

      Chronicle.append("user-1", %UserRegistered{}, concurrency_scope: scope)
  """
  @spec expecting_no_matching_event([option()]) :: t()
  def expecting_no_matching_event(opts \\ []) do
    new(@unset_sequence_number, Keyword.put(opts, :expects_no_matching_event, true))
  end

  @doc """
  Returns the sentinel scope representing no explicit concurrency constraint.
  """
  @spec none() :: t()
  def none, do: new(@unset_sequence_number)

  @doc false
  @spec normalize(t() | keyword() | nil) :: t()
  def normalize(nil), do: none()

  def normalize(%__MODULE__{} = scope) do
    new(scope.sequence_number,
      event_source_id: scope.event_source_id,
      event_stream_type: scope.event_stream_type,
      event_stream_id: scope.event_stream_id,
      event_source_type: scope.event_source_type,
      event_types: scope.event_types,
      expects_no_matching_event: scope.expects_no_matching_event
    )
  end

  def normalize(opts) when is_list(opts) do
    case Keyword.pop(opts, :sequence_number) do
      {nil, _opts} ->
        raise ArgumentError,
              "expected :sequence_number in :concurrency_scope options, got: #{inspect(opts)}"

      {sequence_number, remaining_opts} ->
        new(sequence_number, remaining_opts)
    end
  end

  def normalize(other) do
    raise ArgumentError,
          "expected concurrency scope to be nil, keyword options, or #{inspect(__MODULE__)}, got: #{inspect(other)}"
  end

  defp normalize_string(nil), do: ""
  defp normalize_string(value) when is_binary(value), do: value
  defp normalize_string(value) when is_atom(value), do: Atom.to_string(value)

  defp normalize_string(value) do
    raise ArgumentError,
          "expected concurrency scope value to be a string, atom, or nil, got: #{inspect(value)}"
  end

  defp normalize_event_types(nil), do: []

  defp normalize_event_types(event_types) when is_list(event_types) do
    Enum.uniq(event_types)
  end

  defp normalize_event_types(other) do
    raise ArgumentError,
          "expected :event_types to be a list of event type modules, got: #{inspect(other)}"
  end
end
