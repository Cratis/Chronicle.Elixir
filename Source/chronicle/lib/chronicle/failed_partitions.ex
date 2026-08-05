# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.FailedPartitions do
  @moduledoc """
  Idiomatic API for working with Chronicle failed partitions.

  A partition (an event source, within an observer's subscription) is marked
  failed when a reactor, reducer, or other observer's handling of an event
  raises or returns an error. Failed partitions stop advancing until they are
  retried or the observer is replayed.

  Mirrors the C# and Kotlin clients' `IFailedPartitions`.

  ## Options

    * `:client` — the client name (default: `Chronicle.Client`)
    * `:namespace` — accepted for consistency with other APIs and ignored here
  """

  alias Chronicle.Connections.Connection

  alias Cratis.Chronicle.Contracts.Observation.{
    FailedPartitions,
    GetFailedPartitionsRequest
  }

  defmodule Attempt do
    @moduledoc """
    A single failed attempt to observe a partition.
    """

    @enforce_keys [:sequence_number, :messages, :stack_trace]
    defstruct occurred: nil, sequence_number: 0, messages: [], stack_trace: ""

    @type t :: %__MODULE__{
            occurred: DateTime.t() | String.t() | nil,
            sequence_number: non_neg_integer(),
            messages: [String.t()],
            stack_trace: String.t()
          }
  end

  defmodule FailedPartition do
    @moduledoc """
    A partition that failed to be observed, along with its failed attempts.
    """

    @enforce_keys [:id, :observer_id, :partition, :attempts]
    defstruct id: nil, observer_id: nil, partition: nil, attempts: []

    @type t :: %__MODULE__{
            id: String.t() | nil,
            observer_id: String.t() | nil,
            partition: String.t() | nil,
            attempts: [Attempt.t()]
          }
  end

  @doc """
  Gets all failed partitions for any observer (reactor, reducer, ++) on the
  current event store.
  """
  @spec get_all(keyword()) :: {:ok, [FailedPartition.t()]} | {:error, term()}
  def get_all(opts \\ []), do: get_failed_partitions("", opts)

  @doc """
  Gets all failed partitions for a specific observer.
  """
  @spec get_for(String.t(), keyword()) :: {:ok, [FailedPartition.t()]} | {:error, term()}
  def get_for(observer_id, opts \\ []) when is_binary(observer_id) do
    get_failed_partitions(observer_id, opts)
  end

  defp get_failed_partitions(observer_id, opts) do
    with {:ok, channel, config} <- resolve_channel(opts) do
      namespace = Keyword.get(opts, :namespace, config.namespace)

      request =
        struct(GetFailedPartitionsRequest,
          EventStore: config.event_store,
          Namespace: namespace,
          ObserverId: observer_id
        )

      case FailedPartitions.Stub.get_failed_partitions(channel, request) do
        {:ok, response} ->
          failed_partitions =
            response
            |> Map.get(:items, [])
            |> Enum.map(&decode_failed_partition/1)

          {:ok, failed_partitions}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc false
  def decode_failed_partition(failed_partition) do
    %FailedPartition{
      id: decode_guid(Map.get(failed_partition, :Id)),
      observer_id: Map.get(failed_partition, :ObserverId, ""),
      partition: Map.get(failed_partition, :Partition, ""),
      attempts: Map.get(failed_partition, :Attempts, []) |> Enum.map(&decode_attempt/1)
    }
  end

  defp decode_attempt(attempt) do
    %Attempt{
      occurred: decode_timestamp(Map.get(attempt, :Occurred)),
      sequence_number: Map.get(attempt, :SequenceNumber, 0),
      messages: Map.get(attempt, :Messages, []),
      stack_trace: Map.get(attempt, :StackTrace, "")
    }
  end

  defp decode_guid(nil), do: nil

  defp decode_guid(guid) when is_map(guid) do
    Map.get(guid, :Value, Map.get(guid, :value))
  end

  defp decode_guid(guid), do: guid

  defp decode_timestamp(nil), do: nil

  defp decode_timestamp(value) when is_map(value) do
    cond do
      Map.has_key?(value, :Value) -> decode_timestamp_value(Map.get(value, :Value))
      Map.has_key?(value, :value) -> decode_timestamp_value(Map.get(value, :value))
      true -> value
    end
  end

  defp decode_timestamp(value) when is_binary(value), do: decode_timestamp_value(value)
  defp decode_timestamp(value), do: value

  defp decode_timestamp_value(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, occurred, _offset} -> occurred
      _ -> value
    end
  end

  defp decode_timestamp_value(value), do: value

  defp resolve_channel(opts) do
    client = Keyword.get(opts, :client, Chronicle.Client)

    case Chronicle.Client.config(client) do
      config when is_map(config) ->
        case Connection.channel(config.connection) do
          {:ok, channel} -> {:ok, channel, config}
          error -> error
        end

      _ ->
        {:error, :no_client}
    end
  end
end
