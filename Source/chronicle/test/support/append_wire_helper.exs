# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.AppendWireCase do
  use ExUnit.CaseTemplate

  alias Cratis.Chronicle.Contracts.Clients.{CompatibilityRequest, CompatibilityResponse}
  alias Cratis.Chronicle.Contracts.Sequences, as: Wire

  defmodule Event do
    use Chronicle.Events.EventType, id: "append-wire-event"
    defstruct [:some_value]
  end

  defmodule Interceptor do
    def call(stream, request, _next, opts) do
      Chronicle.AppendWireCase.respond(stream, request, opts)
    end
  end

  using do
    quote do
      alias Chronicle.AppendWireCase.Event
      alias Chronicle.EventSequences.{EventForEventSourceId, EventLog}
      alias Chronicle.Transactions.UnitOfWork
      alias Cratis.Chronicle.Contracts.Sequences, as: Wire
      import Chronicle.AppendWireCase, only: [append: 2, take_request: 0, put_response: 2]
    end
  end

  setup do
    responses = start_supervised!({Agent, fn -> %{} end})
    Process.put(:wire_responses, responses)

    channel = %GRPC.Channel{
      host: "append-test",
      port: 0,
      adapter_payload: %{conn_pid: self()},
      interceptors: [{Interceptor, [owner: self(), responses: responses]}]
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
    %{opts: [client: client], connection: connection, responses: responses}
  end

  def put_response(key, value) do
    Agent.update(Process.get(:wire_responses), &Map.put(&1, key, value))
  end

  # Run the actual generated codecs in both directions, keeping the transport
  # deterministic and local. No generated module is replaced or patched.
  def respond(stream, request, opts) do
    decoded = request.__struct__.decode(request.__struct__.encode(request))
    send(Keyword.fetch!(opts, :owner), {:wire_request, decoded})
    responses = Agent.get(Keyword.fetch!(opts, :responses), & &1)

    response =
      case request do
        %CompatibilityRequest{} ->
          Map.get(responses, :compatibility_response, %CompatibilityResponse{
            IsCompatible: true,
            ServerVersion: "18.3.0",
            ServerProtocolVersion: "18.3.0"
          })

        _ ->
          payload_module =
            if match?(%Wire.AppendRequest{}, request),
              do: Wire.AppendResponse,
              else: Wire.AppendManyResponse

          payload = struct(payload_module, Map.get(responses, :append_payload, IsSuccess: true))

          struct(
            stream.response_mod,
            Keyword.merge(
              [IsAuthorized: true, Response: payload],
              Map.get(responses, :envelope, [])
            )
          )
      end

    case response do
      {:error, _} = error -> error
      _ -> {:ok, response.__struct__.decode(response.__struct__.encode(response))}
    end
  end

  def append(:single, opts),
    do: Chronicle.EventSequences.EventLog.append("source", %Event{some_value: 42}, opts)

  def append(:ordinary, opts),
    do: Chronicle.EventSequences.EventLog.append_many("source", [%Event{some_value: 42}], opts)

  def append(:rich, opts) do
    {metadata, options} =
      Keyword.split(opts, [
        :event_source_type,
        :event_stream_type,
        :event_stream_id,
        :tags,
        :subject,
        :occurred,
        :concurrency_scope,
        :identity,
        :causation
      ])

    entry =
      struct(
        Chronicle.EventSequences.EventForEventSourceId,
        Keyword.merge([event_source_id: "source", event: %Event{some_value: 42}], metadata)
      )

    Chronicle.EventSequences.EventLog.append_many_for_event_sources([entry], options)
  end

  def append(:transaction, opts) do
    unit =
      Chronicle.Transactions.UnitOfWork.begin(
        correlation_id: Keyword.get(opts, :correlation_id, "00112233-4455-6677-8899-aabbccddeeff")
      )

    :ok = append(:ordinary, opts)
    result = Chronicle.Transactions.UnitOfWork.commit(unit)

    if not Chronicle.Transactions.UnitOfWork.is_completed?(unit),
      do: Chronicle.Transactions.UnitOfWork.rollback(unit)

    result
  end

  def take_request do
    receive do
      {:wire_request, %CompatibilityRequest{}} -> take_request()
      {:wire_request, request} -> request
    after
      1000 -> raise "append request was not sent"
    end
  end
end
