# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Observers.BatchContext do
  @moduledoc """
  Describes the page of events a batch function is called for. It is the second argument of a
  reactor batch function and the third of a reducer batch function, and is passed to batch
  functions only — per-event `handle/2` and `reduce/3` receive a `Chronicle.Events.EventContext`.

    * `:observer_id`, `:event_store`, `:namespace`, `:event_sequence_id` — who is observing what
    * `:origin` — where the page came from:
      * `:live` — the events were appended now and delivered to an observer that is up to date
      * `:catch_up` — read from storage for an observer that is behind
      * `:replay` — read from storage for an observer that was rewound
      * `:retry` — read from storage to recover a failed or deferred partition
      * `:unknown` — a kernel that does not say
    * `:partitions` — the partitions (event source ids) in the page
    * `:event_count`, `:first_sequence_number`, `:last_sequence_number` — the page's events
    * `:deadline` — the monotonic time (milliseconds, `System.monotonic_time(:millisecond)`) the
      kernel waits for the result until, or `nil` when it waits without a deadline
    * `:can_defer?` — whether the kernel understands deferrals (it delivered a page)
  """

  alias Chronicle.Observers.PageMessages

  @typedoc "Where a page came from."
  @type origin :: :live | :catch_up | :replay | :retry | :unknown

  @type t :: %__MODULE__{
          observer_id: String.t(),
          event_store: String.t(),
          namespace: String.t(),
          event_sequence_id: String.t(),
          origin: origin(),
          partitions: [String.t()],
          event_count: non_neg_integer(),
          first_sequence_number: non_neg_integer(),
          last_sequence_number: non_neg_integer(),
          deadline: integer() | nil,
          can_defer?: boolean()
        }

  defstruct observer_id: "",
            event_store: "",
            namespace: "",
            event_sequence_id: "event-log",
            origin: :unknown,
            partitions: [],
            event_count: 0,
            first_sequence_number: 0,
            last_sequence_number: 0,
            deadline: nil,
            can_defer?: false

  @doc "Whether the page is part of a replay."
  @spec replay?(t()) :: boolean()
  def replay?(%__MODULE__{origin: origin}), do: origin == :replay

  @doc false
  @spec for_message(map(), keyword()) :: t()
  def for_message(message, opts) do
    partitions = PageMessages.partitions_of(message)

    sequence_numbers =
      Enum.flat_map(partitions, fn p -> Enum.map(p.events, &PageMessages.sequence_number/1) end)

    deadline =
      case Map.get(message, :DeliverWithinMilliseconds, 0) do
        within when is_integer(within) and within > 0 ->
          Keyword.get(opts, :received_at, System.monotonic_time(:millisecond)) + within

        _ ->
          nil
      end

    %__MODULE__{
      observer_id: Keyword.get(opts, :observer_id, ""),
      event_store: Keyword.get(opts, :event_store, "") || "",
      namespace: Keyword.get(opts, :namespace, "") || "",
      event_sequence_id: Keyword.get(opts, :event_sequence_id, "event-log"),
      origin: PageMessages.origin(message),
      partitions: Enum.map(partitions, & &1.partition),
      event_count: length(sequence_numbers),
      first_sequence_number: if(sequence_numbers == [], do: 0, else: Enum.min(sequence_numbers)),
      last_sequence_number: if(sequence_numbers == [], do: 0, else: Enum.max(sequence_numbers)),
      deadline: deadline,
      can_defer?: PageMessages.paged?(message)
    }
  end
end
