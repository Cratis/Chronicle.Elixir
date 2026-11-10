# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Imports.Calls do
  @moduledoc false

  # The gRPC calls of the `Imports` service. Every call resolves the channel afresh, so an
  # import continues over a reconnected connection.

  alias Chronicle.Connections.Connection
  alias Chronicle.Imports.Wire
  alias Chronicle.WireResult

  alias Cratis.Chronicle.Contracts.Imports.{
    AbandonImportRequest,
    AddImportChunkRequest,
    BeginImportRequest,
    CompleteImportRequest,
    GetImportRequest,
    Imports,
    ObserveImportRequest
  }

  # Unavailable, DeadlineExceeded, ResourceExhausted, Aborted and Internal: the connection
  # failed rather than the kernel refusing the chunk, so sending it again is worth it.
  @transient_statuses [14, 4, 8, 10, 13]
  @unimplemented 12
  @default_timeout 60_000

  @type target :: %{
          required(:config) => map(),
          required(:namespace) => String.t(),
          optional(:timeout) => timeout()
        }

  @spec resolve(keyword()) :: {:ok, target()} | {:error, term()}
  def resolve(opts) do
    case Chronicle.Client.config(Keyword.get(opts, :client, Chronicle.Client)) do
      config when is_map(config) ->
        {:ok,
         %{
           config: config,
           namespace: Keyword.get(opts, :namespace) || config.namespace,
           timeout: Keyword.get(opts, :timeout, @default_timeout)
         }}

      _ ->
        {:error, :no_client}
    end
  end

  @spec begin(target(), String.t(), :reject | :skip, String.t() | nil) ::
          {:ok, map()} | {:error, term()}
  def begin(target, event_sequence_id, on_invalid, import_id) do
    request = %BeginImportRequest{
      EventStore: target.config.event_store,
      Namespace: target.namespace,
      EventSequenceId: event_sequence_id,
      OnInvalid: Wire.on_invalid(on_invalid),
      ImportId: Wire.guid(import_id)
    }

    with {:ok, response} <- call(target, :begin_import, request) do
      case Wire.blank_to_nil(response && Map.get(response, :Error)) do
        nil -> {:ok, response}
        error -> {:error, {:import_could_not_begin, error}}
      end
    end
  end

  @spec add_chunk(target(), String.t(), non_neg_integer(), non_neg_integer(), [struct()], map()) ::
          {:ok, map()} | {:error, term()}
  def add_chunk(target, import_id, chunk_index, first_event_index, events, retry) do
    request = %AddImportChunkRequest{
      EventStore: target.config.event_store,
      Namespace: target.namespace,
      ImportId: Wire.guid(import_id),
      ChunkIndex: chunk_index,
      FirstEventIndex: first_event_index,
      Events: events
    }

    send_chunk(target, request, retry, 1)
  end

  @spec complete(target(), String.t(), non_neg_integer(), non_neg_integer()) ::
          {:ok, map()} | {:error, term()}
  def complete(target, import_id, expected_chunks, expected_events) do
    call(target, :complete_import, %CompleteImportRequest{
      EventStore: target.config.event_store,
      Namespace: target.namespace,
      ImportId: Wire.guid(import_id),
      ExpectedChunks: expected_chunks,
      ExpectedEvents: expected_events
    })
  end

  @spec abandon(target(), String.t()) :: {:ok, map()} | {:error, term()}
  def abandon(target, import_id) do
    call(target, :abandon_import, %AbandonImportRequest{
      EventStore: target.config.event_store,
      Namespace: target.namespace,
      ImportId: Wire.guid(import_id)
    })
  end

  @spec get(target(), String.t()) :: {:ok, map() | nil} | {:error, term()}
  def get(target, import_id) do
    call(target, :get_import, %GetImportRequest{
      EventStore: target.config.event_store,
      Namespace: target.namespace,
      ImportId: Wire.guid(import_id)
    })
  end

  @spec observe(target(), String.t()) :: {:ok, Enumerable.t()} | {:error, term()}
  def observe(target, import_id) do
    request = %ObserveImportRequest{
      EventStore: target.config.event_store,
      Namespace: target.namespace,
      ImportId: Wire.guid(import_id)
    }

    with {:ok, channel} <- Connection.channel(target.config.connection) do
      Imports.Stub.observe_import(channel, request) |> unimplemented_as_unsupported()
    end
  end

  defp send_chunk(target, request, retry, attempt) do
    case call(target, :add_import_chunk, request) do
      {:ok, response} ->
        chunk_response(request."ChunkIndex", response)

      {:error, %GRPC.RPCError{status: status}}
      when status in @transient_statuses and attempt < retry.max_attempts ->
        # Sending the chunk again is safe: the kernel stages a chunk under its index once.
        Process.sleep(retry.delay.(attempt))
        send_chunk(target, request, retry, attempt + 1)

      {:error, _} = error ->
        error
    end
  end

  defp chunk_response(chunk_index, response) do
    cond do
      is_nil(response) ->
        {:error, {:import_chunk_not_acknowledged, chunk_index}}

      error = Wire.blank_to_nil(Map.get(response, :Error)) ->
        {:error, {:import_chunk_refused, chunk_index, error}}

      Map.get(response, :ChunkIndex) != chunk_index ->
        {:error,
         {:import_chunk_acknowledged_out_of_order, chunk_index, Map.get(response, :ChunkIndex)}}

      true ->
        {:ok, response}
    end
  end

  defp call(target, rpc, request) do
    with {:ok, channel} <- Connection.channel(target.config.connection) do
      case apply(Imports.Stub, rpc, [channel, request, [timeout: target.timeout]]) do
        {:ok, envelope} -> WireResult.unwrap(envelope)
        error -> unimplemented_as_unsupported(error)
      end
    end
  end

  # A kernel without the Imports service answers Unimplemented.
  defp unimplemented_as_unsupported({:error, %GRPC.RPCError{status: @unimplemented}}),
    do: {:error, :imports_not_supported}

  defp unimplemented_as_unsupported(other), do: other
end
