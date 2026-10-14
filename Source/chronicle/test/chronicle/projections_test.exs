# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.ProjectionsTest do
  use ExUnit.Case, async: false

  alias Chronicle.Projections

  alias Cratis.Chronicle.Contracts.Projections.{
    IEnumerable_ProjectionWithDeclaration,
    OneOf_ProjectionPreview_ProjectionDeclarationParsingErrors,
    ProjectionDeclarationParsingErrors,
    ProjectionDeclarationSyntaxError,
    ProjectionPreview,
    ProjectionWithDeclaration
  }

  alias Cratis.Chronicle.Contracts.Observation.{
    AllObserversRequest,
    IEnumerable_ObserverInformation,
    ObserverInformation
  }

  defmodule Order do
    use Chronicle.ReadModels.ReadModel
    defstruct id: "", status: "new"
  end

  defmodule Interceptor do
    def call(_stream, request, _next, opts) do
      responder = Agent.get(Keyword.fetch!(opts, :agent), & &1)
      response = responder.(request)
      {:ok, response.__struct__.decode(response.__struct__.encode(response))}
    end
  end

  setup do
    {:ok, agent} =
      Agent.start_link(fn ->
        fn request -> raise "no responder configured for #{inspect(request)}" end
      end)

    channel = %GRPC.Channel{
      host: "projections-test",
      port: 0,
      adapter_payload: %{conn_pid: self()},
      interceptors: [{Interceptor, [agent: agent]}]
    }

    connection =
      start_supervised!(
        {Chronicle.Connections.Connection,
         connect_fun: fn _, _ -> {:ok, channel} end, disconnect_fun: fn _ -> :ok end}
      )

    :ok = Chronicle.Connections.Connection.connect(connection)
    client = make_ref()

    :persistent_term.put({Chronicle.Client, client}, %{
      connection: connection,
      event_store: "store",
      namespace: "namespace"
    })

    on_exit(fn -> :persistent_term.erase({Chronicle.Client, client}) end)

    %{opts: [client: client], agent: agent}
  end

  defp respond(agent, fun), do: Agent.update(agent, fn _ -> fun end)

  describe "query/2" do
    test "decodes successful entries as plain maps by default", %{opts: opts, agent: agent} do
      respond(agent, fn _request ->
        struct(OneOf_ProjectionPreview_ProjectionDeclarationParsingErrors,
          Value0:
            struct(ProjectionPreview,
              ReadModelEntries: [Jason.encode!(%{id: "order-1", status: "placed"})]
            )
        )
      end)

      assert {:ok, result} = Projections.query("projection Orders\n  from OrderPlaced", opts)
      assert result.instances == [%{"id" => "order-1", "status" => "placed"}]
      assert result.total_count == 1
    end

    test "decodes entries as a struct when :read_model is given", %{opts: opts, agent: agent} do
      respond(agent, fn _request ->
        struct(OneOf_ProjectionPreview_ProjectionDeclarationParsingErrors,
          Value0:
            struct(ProjectionPreview,
              ReadModelEntries: [Jason.encode!(%{id: "order-1", status: "placed"})]
            )
        )
      end)

      assert {:ok, result} =
               Projections.query(
                 "projection Orders => Order\n  from OrderPlaced",
                 Keyword.put(opts, :read_model, Order)
               )

      assert result.instances == [%Order{id: "order-1", status: "placed"}]
    end

    test "returns invalid_declaration with the syntax errors", %{opts: opts, agent: agent} do
      respond(agent, fn _request ->
        struct(OneOf_ProjectionPreview_ProjectionDeclarationParsingErrors,
          Value1:
            struct(ProjectionDeclarationParsingErrors,
              Errors: [
                struct(ProjectionDeclarationSyntaxError, Message: "bad token", Line: 2, Column: 3)
              ]
            )
        )
      end)

      assert {:error, {:invalid_declaration, [%{message: "bad token", line: 2, column: 3}]}} =
               Projections.query("not pdl", opts)
    end
  end

  describe "preview/2" do
    test "looks up the read model's own declaration and queries it", %{opts: opts, agent: agent} do
      respond(agent, fn
        %Cratis.Chronicle.Contracts.Projections.GetAllDeclarationsRequest{} ->
          struct(IEnumerable_ProjectionWithDeclaration,
            items: [
              struct(ProjectionWithDeclaration,
                Identifier: Order.__chronicle_read_model__(:id),
                ContainerName: "orders",
                Declaration: "projection Orders => Order\n  from OrderPlaced"
              )
            ]
          )

        %Cratis.Chronicle.Contracts.Projections.PreviewProjectionRequest{} ->
          struct(OneOf_ProjectionPreview_ProjectionDeclarationParsingErrors,
            Value0:
              struct(ProjectionPreview,
                ReadModelEntries: [Jason.encode!(%{id: "order-1", status: "placed"})]
              )
          )
      end)

      assert {:ok, result} = Projections.preview(Order, opts)
      assert result.instances == [%Order{id: "order-1", status: "placed"}]
    end

    test "returns unknown_projection when no declaration matches", %{opts: opts, agent: agent} do
      respond(agent, fn %Cratis.Chronicle.Contracts.Projections.GetAllDeclarationsRequest{} ->
        struct(IEnumerable_ProjectionWithDeclaration, items: [])
      end)

      assert Projections.preview(Order, opts) == {:error, {:unknown_projection, Order}}
    end
  end

  describe "wait_for/3" do
    test "returns :ok once the observer has handled the sequence number", %{
      opts: opts,
      agent: agent
    } do
      counter = :counters.new(1, [])

      respond(agent, fn %AllObserversRequest{} ->
        attempt = :counters.get(counter, 1)
        :counters.add(counter, 1, 1)
        last_handled = if attempt < 2, do: 3, else: 10

        struct(IEnumerable_ObserverInformation,
          items: [
            struct(ObserverInformation,
              Id: Order.__chronicle_read_model__(:id),
              LastHandledEventSequenceNumber: last_handled
            )
          ]
        )
      end)

      assert Projections.wait_for(Order, 10, Keyword.merge(opts, interval: 1, timeout: 1_000)) ==
               :ok

      assert :counters.get(counter, 1) >= 3
    end

    test "returns {:error, :timeout} when the sequence number is never reached", %{
      opts: opts,
      agent: agent
    } do
      respond(agent, fn %AllObserversRequest{} ->
        struct(IEnumerable_ObserverInformation,
          items: [
            struct(ObserverInformation,
              Id: Order.__chronicle_read_model__(:id),
              LastHandledEventSequenceNumber: 0
            )
          ]
        )
      end)

      assert Projections.wait_for(Order, 10, Keyword.merge(opts, interval: 1, timeout: 20)) ==
               {:error, :timeout}
    end
  end
end
