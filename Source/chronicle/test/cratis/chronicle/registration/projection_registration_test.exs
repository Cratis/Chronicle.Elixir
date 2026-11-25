# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Cratis.Chronicle.Registration.ProjectionRegistrationTest do
  use ExUnit.Case, async: true

  alias Cratis.Chronicle.Registration.Coordinator
  alias Cratis.Chronicle.Registration.RetryPolicy
  alias Cratis.Chronicle.Contracts.Projections.{RegisterRequest, RegistrationStatus}

  defmodule SomeEvent do
    use Cratis.Chronicle.Events.EventType, id: "projection-registration-test-some-event"
    defstruct [:name]
  end

  defmodule SomeReadModel do
    use Cratis.Chronicle.ReadModels.ReadModel
    defstruct id: nil, name: nil
    from(SomeEvent, set: [id: :event_source_id, name: :name])
  end

  defmodule Interceptor do
    # Answers every projection call, telling the test what was asked. Registration status
    # requests are answered from `statuses`, one per request; the last one repeats.
    def call(stream, request, _next, opts) do
      owner = Keyword.fetch!(opts, :owner)
      send(owner, {:projection_call, stream.rpc, request})

      case stream.rpc do
        {:GetRegistrationStatus, _, _, _} -> status(Keyword.fetch!(opts, :statuses))
        _ -> {:ok, %Google.Protobuf.Empty{}}
      end
    end

    defp status(statuses) do
      next =
        Agent.get_and_update(statuses, fn
          [last] -> {last, [last]}
          [first | rest] -> {first, rest}
        end)

      case next do
        {:error, _} = error -> error
        status -> {:ok, struct(RegistrationStatus, status)}
      end
    end
  end

  defp fake_channel(statuses \\ [[State: :Applied]]) do
    agent = start_supervised!({Agent, fn -> statuses end}, id: make_ref())

    %GRPC.Channel{
      host: "projection-registration-test",
      port: 0,
      adapter_payload: %{conn_pid: self()},
      interceptors: [{Interceptor, [owner: self(), statuses: agent]}]
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

  describe "registering projections as a registrant" do
    defp registrant_state(extra \\ []) do
      Map.merge(
        state(),
        Map.new(
          [registrant: "my_app", accepted_registration: [sleep_fun: fn _ -> :ok end]] ++ extra
        )
      )
    end

    test "names the registrant and, not claiming to be the full set, asks for its status" do
      assert :ok = Coordinator.register_projections(fake_channel(), registrant_state())

      assert_receive {:projection_call, {:Register, _, _, _}, %RegisterRequest{} = request}
      assert request."Registrant" == "my_app"
      assert request."FullSet" == false

      assert_receive {:projection_call, {:GetRegistrationStatus, _, _, _}, status_request}
      assert status_request."Registrant" == "my_app"
      assert status_request."EventStore" == "store"
    end

    test "polls until the kernel has applied the registration, waiting longer each time" do
      test = self()
      channel = fake_channel([[State: :Pending], [State: :Pending], [State: :Applied]])

      state =
        registrant_state(
          accepted_registration: [sleep_fun: fn delay -> send(test, {:slept, delay}) end]
        )

      assert :ok = Coordinator.register_projections(channel, state)

      assert_receive {:slept, 50}
      assert_receive {:slept, 100}
      refute_receive {:slept, _}, 50
    end

    test "never waits longer than two seconds between polls" do
      test = self()
      pending = List.duplicate([State: :Pending], 9) ++ [[State: :Applied]]

      state =
        registrant_state(
          accepted_registration: [sleep_fun: fn delay -> send(test, {:slept, delay}) end]
        )

      assert :ok = Coordinator.register_projections(fake_channel(pending), state)

      delays = for _ <- 1..9, do: receive(do: ({:slept, delay} -> delay))
      assert delays == [50, 100, 200, 400, 800, 1600, 2000, 2000, 2000]
    end

    test "fails, and is not retried, when the kernel could not apply the registration" do
      channel = fake_channel([[State: :Failed, Failure: "the read model is gone"]])

      assert {:error, {:register_projections, reason}} =
               Coordinator.register_projections(channel, registrant_state())

      assert reason ==
               {:projection_registration_not_applied, "my_app", "the read model is gone"}

      refute RetryPolicy.retryable?({:register_projections, reason})
    end

    test "carries on when the kernel has no registration status to give" do
      channel = fake_channel([{:error, %GRPC.RPCError{status: 12, message: "unimplemented"}}])

      assert :ok = Coordinator.register_projections(channel, registrant_state())
    end

    test "fails retryably when the kernel is unavailable" do
      channel = fake_channel([{:error, %GRPC.RPCError{status: 14, message: "busy"}}])

      assert {:error,
              {:register_projections, {:registration_status, %GRPC.RPCError{status: 14}}} = error} =
               Coordinator.register_projections(channel, registrant_state())

      assert RetryPolicy.retryable?(error)
    end

    test "carries on when the wait for the kernel to finish applying is over" do
      {:ok, clock} = Agent.start_link(fn -> 0 end)

      state =
        registrant_state(
          accepted_registration: [
            max_wait: 1_000,
            sleep_fun: fn _ -> :ok end,
            now_fun: fn -> Agent.get_and_update(clock, &{&1, &1 + 600}) end
          ]
        )

      assert :ok = Coordinator.register_projections(fake_channel([[State: :Pending]]), state)
    end
  end
end
