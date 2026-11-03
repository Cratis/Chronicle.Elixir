# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Observers.PageMessages do
  @moduledoc false

  # Reads the deliveries a reactor or reducer receives, which hold either one partition
  # (the legacy shape: `Partition` and `Events`, plus `InitialState` for reducers) or a
  # page of partitions (`Partitions`). A kernel that predates pages always sends the
  # legacy shape; a kernel that knows pages sends `Partitions` to a client that opted in.

  @typedoc "One partition of a delivery."
  @type partition :: %{partition: String.t(), events: [map()], initial_state: String.t()}

  @doc "Whether the kernel delivered a page (and so understands per-partition results and deferrals)."
  @spec paged?(map()) :: boolean()
  def paged?(message), do: wire_partitions(message) != []

  @doc "The partitions of a delivery, treating a single-partition delivery as a page of one."
  @spec partitions_of(map()) :: [partition()]
  def partitions_of(message) do
    case wire_partitions(message) do
      [] ->
        [
          %{
            partition: Map.get(message, :Partition, "") || "",
            events: Map.get(message, :Events, []) || [],
            initial_state: Map.get(message, :InitialState, "") || ""
          }
        ]

      partitions ->
        Enum.map(partitions, fn partition ->
          %{
            partition: Map.get(partition, :Partition, "") || "",
            events: Map.get(partition, :Events, []) || [],
            initial_state: Map.get(partition, :InitialState, "") || ""
          }
        end)
    end
  end

  @doc """
  The partition a delivery is scheduled under, so deliveries for the same partition run in
  order, or `:page` when it spans several partitions and must run on its own.
  """
  @spec scheduling_partition(map()) :: {:partition, String.t()} | :page
  def scheduling_partition(message) do
    case wire_partitions(message) do
      [] -> {:partition, Map.get(message, :Partition, "") || ""}
      [single] -> {:partition, Map.get(single, :Partition, "") || ""}
      _ -> :page
    end
  end

  @doc "How many events a delivery holds, across its partitions."
  @spec event_count(map()) :: non_neg_integer()
  def event_count(message),
    do: message |> partitions_of() |> Enum.reduce(0, &(length(&1.events) + &2))

  @doc "Where the delivery came from: `:live`, `:catch_up`, `:replay`, `:retry` or `:unknown`."
  @spec origin(map()) :: Chronicle.Observers.BatchContext.origin()
  def origin(message) do
    case Map.get(message, :Origin) do
      live when live in [:Live, 1] -> :live
      catching_up when catching_up in [:CatchingUp, 2] -> :catch_up
      replaying when replaying in [:Replaying, 3] -> :replay
      retrying when retrying in [:Retrying, 4] -> :retry
      _ -> :unknown
    end
  end

  @doc "The sequence number of an appended event on the wire."
  @spec sequence_number(map()) :: non_neg_integer()
  def sequence_number(appended_event),
    do: Map.get(Map.get(appended_event, :Context, %{}) || %{}, :SequenceNumber, 0) || 0

  @doc "The event type id of an appended event on the wire."
  @spec event_type_id(map()) :: String.t()
  def event_type_id(appended_event) do
    context = Map.get(appended_event, :Context, %{}) || %{}
    event_type = Map.get(context, :EventType, %{}) || %{}
    Map.get(event_type, :Id, "") || ""
  end

  defp wire_partitions(message), do: Map.get(message, :Partitions, []) || []
end
