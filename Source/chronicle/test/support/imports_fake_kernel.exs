# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.ImportsFakeKernel do
  @moduledoc false

  # A deterministic, in-process stand-in for the kernel's Imports service. Requests go
  # through the real generated stub and codecs; an interceptor on a fake channel answers
  # them from an Agent holding the import, so specs can observe chunking, concurrency and
  # retries without a kernel.

  use ExUnit.CaseTemplate

  alias Cratis.Chronicle.Contracts.Clients.{CompatibilityRequest, CompatibilityResponse}
  alias Cratis.Chronicle.Contracts.Imports, as: Wire

  @import_id "0f8fad5b-d9cb-469f-a165-70867728950e"

  defmodule Event do
    use Chronicle.Events.EventType, id: "imported-event"
    defstruct n: 0, payload: ""
  end

  defmodule Interceptor do
    def call(stream, request, _next, opts),
      do: Chronicle.ImportsFakeKernel.respond(stream, request, opts)
  end

  using do
    quote do
      alias Chronicle.EventSequences.EventForEventSourceId
      alias Chronicle.Imports
      alias Chronicle.Imports.{ImportProgress, ImportRejection, ImportResult}
      alias Chronicle.ImportsFakeKernel, as: Kernel
      alias Chronicle.ImportsFakeKernel.Event
      alias Cratis.Chronicle.Contracts.Imports, as: Wire
    end
  end

  setup context do
    kernel = start_supervised!({Agent, fn -> initial(Map.get(context, :kernel_config, [])) end})

    channel = %GRPC.Channel{
      host: "imports-test",
      port: 0,
      adapter_payload: %{conn_pid: self()},
      interceptors: [{Interceptor, [owner: self(), kernel: kernel]}]
    }

    connection =
      start_supervised!(
        {Chronicle.Connections.Connection,
         connect_fun: fn _, _ -> {:ok, channel} end, disconnect_fun: fn _ -> :ok end}
      )

    :ok = Chronicle.Connections.Connection.connect(connection)
    client = self()

    :persistent_term.put({Chronicle.Client, client}, %{
      connection: connection,
      event_store: "store",
      namespace: "namespace"
    })

    on_exit(fn -> :persistent_term.erase({Chronicle.Client, client}) end)
    %{opts: [client: client, retry_delay: fn _ -> 1 end, poll_interval: 1], kernel: kernel}
  end

  def import_id, do: @import_id

  def events(count, opts \\ []) do
    payload = Keyword.get(opts, :payload, "")

    Stream.map(0..(count - 1)//1, fn n ->
      %Chronicle.EventSequences.EventForEventSourceId{
        event_source_id: "source-#{n}",
        event: %Event{n: n, payload: payload}
      }
    end)
  end

  @doc "Everything the kernel was asked, in order, as `{rpc, request}`."
  def state(kernel), do: Agent.get(kernel, & &1)

  def chunk_requests(kernel), do: kernel |> state() |> Map.get(:chunk_requests) |> Enum.reverse()

  defp initial(overrides) do
    Map.merge(
      %{
        max_chunk_events: 1_000,
        max_chunk_bytes: 4_194_304,
        sequence: "event-log",
        on_invalid: :Reject,
        chunk_delay: 0,
        failures: %{},
        refusals: %{},
        reject: fn _event -> nil end,
        unimplemented: false,
        staged: %{},
        chunk_requests: [],
        attempts: %{},
        in_flight: 0,
        peak_in_flight: 0,
        completed: nil,
        abandoned: false,
        log: []
      },
      Map.new(overrides)
    )
  end

  def respond(stream, request, opts) do
    request = request.__struct__.decode(request.__struct__.encode(request))
    kernel = Keyword.fetch!(opts, :kernel)
    send(Keyword.fetch!(opts, :owner), {:import_request, request})

    case handle(request, kernel) do
      {:error, _} = error -> error
      {:stream, payloads} -> {:ok, Stream.map(payloads, &{:ok, envelope(stream, &1)})}
      payload -> {:ok, envelope(stream, payload)}
    end
  end

  defp envelope(_stream, %CompatibilityResponse{} = response), do: response

  defp envelope(stream, payload) do
    field = if Map.has_key?(struct(stream.response_mod), :Response), do: :Response, else: :Data
    response = struct(stream.response_mod, [{:IsAuthorized, true}, {field, payload}])
    response.__struct__.decode(response.__struct__.encode(response))
  end

  defp handle(%CompatibilityRequest{}, _kernel),
    do: %CompatibilityResponse{IsCompatible: true, ServerVersion: "19.149.0"}

  defp handle(request, kernel) do
    if state(kernel).unimplemented,
      do: {:error, %GRPC.RPCError{status: 12, message: "unimplemented"}},
      else: handle_import(request, kernel)
  end

  defp handle_import(%Wire.BeginImportRequest{} = request, kernel) do
    state =
      Agent.get_and_update(kernel, fn s ->
        s = %{s | on_invalid: request."OnInvalid", sequence: request."EventSequenceId"}
        {s, s}
      end)

    %Wire.BeginImportResponse{
      ImportId: request."ImportId" || Chronicle.Imports.Wire.guid(@import_id),
      State: :Open,
      MaxChunkEvents: state.max_chunk_events,
      MaxChunkBytes: state.max_chunk_bytes
    }
  end

  defp handle_import(%Wire.AddImportChunkRequest{} = request, kernel) do
    index = request."ChunkIndex"

    state =
      Agent.get_and_update(kernel, fn s ->
        in_flight = s.in_flight + 1
        attempts = Map.update(s.attempts, index, 1, &(&1 + 1))

        s = %{
          s
          | in_flight: in_flight,
            peak_in_flight: max(s.peak_in_flight, in_flight),
            attempts: attempts,
            chunk_requests: [request | s.chunk_requests],
            log: [{:chunk_sent, index} | s.log]
        }

        {s, s}
      end)

    Process.sleep(state.chunk_delay)
    failure = Map.get(state.failures, {index, Map.get(state.attempts, index)})

    result =
      cond do
        failure != nil ->
          {:error, %GRPC.RPCError{status: failure, message: "transport"}}

        error = Map.get(state.refusals, index) ->
          %Wire.AddImportChunkResponse{ChunkIndex: index, Error: error}

        true ->
          stage(kernel, request)
      end

    Agent.update(kernel, &%{&1 | in_flight: &1.in_flight - 1})
    result
  end

  defp handle_import(%Wire.CompleteImportRequest{} = request, kernel) do
    Agent.update(kernel, &%{&1 | completed: request})
    %Wire.AbandonImportResponse{ImportId: request."ImportId", State: :Validating}
  end

  defp handle_import(%Wire.AbandonImportRequest{} = request, kernel) do
    Agent.update(kernel, &%{&1 | abandoned: true})
    %Wire.AbandonImportResponse{ImportId: request."ImportId", State: :Abandoned}
  end

  defp handle_import(%Wire.GetImportRequest{}, kernel), do: progress(state(kernel))

  # Streams every change of the import until it ends, as the kernel's observable query does.
  defp handle_import(%Wire.ObserveImportRequest{}, kernel) do
    {:stream,
     Stream.unfold(nil, fn
       :done ->
         nil

       last ->
         current = next_change(kernel, last, 1_000)

         {current,
          if(current."State" in [:Completed, :Failed, :Abandoned], do: :done, else: current)}
     end)}
  end

  defp next_change(kernel, last, wait) do
    current = progress(state(kernel))

    if current != last or wait <= 0 do
      current
    else
      Process.sleep(2)
      next_change(kernel, last, wait - 2)
    end
  end

  defp stage(kernel, request) do
    index = request."ChunkIndex"
    first = request."FirstEventIndex"

    Agent.get_and_update(kernel, fn s ->
      already = Map.has_key?(s.staged, index)

      rejections =
        request."Events"
        |> Enum.with_index(first)
        |> Enum.flat_map(fn {event, i} ->
          case s.reject.(event) do
            nil ->
              []

            reasons ->
              [
                %Wire.ImportEventRejection{
                  Index: i,
                  EventType: event."EventType"."Id",
                  Reasons: reasons
                }
              ]
          end
        end)

      staged = Map.put_new(s.staged, index, {first, request."Events", rejections})

      response = %Wire.AddImportChunkResponse{
        ChunkIndex: index,
        AlreadyStaged: already,
        EventsReceived: length(request."Events"),
        EventsStaged: length(request."Events") - length(rejections),
        Rejections: rejections
      }

      {response, %{s | staged: staged}}
    end)
  end

  defp progress(s) do
    chunks = s.staged |> Map.keys() |> Enum.sort()

    acknowledged =
      chunks |> Enum.with_index() |> Enum.take_while(fn {c, i} -> c == i end) |> length()

    events = Enum.flat_map(chunks, fn c -> elem(Map.fetch!(s.staged, c), 1) end)
    rejections = Enum.flat_map(chunks, fn c -> elem(Map.fetch!(s.staged, c), 2) end)

    acknowledged_events =
      chunks
      |> Enum.take(acknowledged)
      |> Enum.map(&length(elem(Map.fetch!(s.staged, &1), 1)))
      |> Enum.sum()

    staged = length(events) - length(rejections)

    {state, committed} =
      cond do
        s.abandoned -> {:Abandoned, 0}
        s.completed == nil -> {:Staging, 0}
        rejections != [] and s.on_invalid == :Reject -> {:Failed, 0}
        true -> {:Completed, staged}
      end

    %Wire.ImportProgressResponse{
      ImportId: Chronicle.Imports.Wire.guid(@import_id),
      EventSequenceId: s.sequence,
      State: state,
      OnInvalid: s.on_invalid,
      StagedChunks: chunks,
      EventsReceived: length(events),
      EventsStaged: staged,
      EventsCommitted: committed,
      RejectedCount: length(rejections),
      Rejections: rejections,
      FirstSequenceNumber: if(committed > 0, do: 10, else: 0),
      LastSequenceNumber: if(committed > 0, do: 9 + committed, else: 0),
      FailureReason:
        if(state == :Failed, do: "#{length(rejections)} events were rejected", else: ""),
      MaxChunkEvents: s.max_chunk_events,
      MaxChunkBytes: s.max_chunk_bytes,
      AcknowledgedChunks: acknowledged,
      AcknowledgedEvents: acknowledged_events
    }
  end
end
