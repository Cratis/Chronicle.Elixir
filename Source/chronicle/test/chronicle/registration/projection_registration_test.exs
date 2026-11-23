# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Registration.ProjectionRegistrationTest do
  use ExUnit.Case, async: true

  alias Chronicle.Registration.Coordinator
  alias Cratis.Chronicle.Contracts.Projections.RegisterRequest

  defmodule SomeEvent do
    use Chronicle.Events.EventType, id: "projection-registration-test-some-event"
    defstruct [:name]
  end

  defmodule SomeReadModel do
    use Chronicle.ReadModels.ReadModel
    defstruct id: nil, name: nil
    from(SomeEvent, set: [id: :event_source_id, name: :name])
  end

  defmodule Interceptor do
    # Answers every projection call, telling the test what was asked.
    def call(stream, request, _next, opts) do
      owner = Keyword.fetch!(opts, :owner)
      send(owner, {:projection_call, stream.rpc, request})
      {:ok, %Google.Protobuf.Empty{}}
    end
  end

  defp fake_channel do
    %GRPC.Channel{
      host: "projection-registration-test",
      port: 0,
      adapter_payload: %{conn_pid: self()},
      interceptors: [{Interceptor, [owner: self()]}]
    }
  end

  defp state do
    %{
      event_store: "store",
      read_models: [SomeReadModel],
      projections: [],
      graphs: [],
      global_handlers: []
    }
  end

  describe "registering projections without a registrant" do
    test "registers once and does not poll for the registration status" do
      assert :ok = Coordinator.register_projections(fake_channel(), state())

      assert_receive {:projection_call, {:Register, _, _, _}, %RegisterRequest{} = request}
      assert request."Registrant" == ""
      assert [_] = request."Projections"
      refute_receive {:projection_call, {:GetRegistrationStatus, _, _, _}, _}, 100
    end
  end
end
