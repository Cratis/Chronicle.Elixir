# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Reactors.HandlerTest do
  use ExUnit.Case, async: true

  alias Chronicle.Connections.Lifecycle
  alias Chronicle.EventSequences.EventForEventSourceId
  alias Chronicle.Reactors.Handler

  defmodule SomeEvent do
    use Chronicle.Events.EventType, id: "some-event"
    defstruct [:value]
  end

  defmodule SideEffectEvent do
    use Chronicle.Events.EventType, id: "side-effect-event"
    defstruct [:value]
  end

  defmodule OtherSideEffectEvent do
    use Chronicle.Events.EventType, id: "other-side-effect-event"
    defstruct [:value]
  end

  defmodule SomeEventV2 do
    use Chronicle.Events.EventType, id: "some-event", generation: 2
    defstruct [:value]
  end

  defmodule PinnedReactor do
    use Chronicle.Reactors.Reactor, generation_delivery: :pinned

    @handles SomeEvent

    @impl true
    def handle(%SomeEvent{}, _context), do: :ok
  end

  defmodule DefaultDeliveryReactor do
    use Chronicle.Reactors.Reactor

    @handles SomeEvent

    @impl true
    def handle(%SomeEvent{}, _context), do: :ok
  end

  defmodule AmbiguousPinReactor do
    use Chronicle.Reactors.Reactor, generation_delivery: :pinned

    @handles SomeEvent
    @handles SomeEventV2

    @impl true
    def handle(_event, _context), do: :ok
  end

  defmodule TestReactor do
    use Chronicle.Reactors.Reactor

    @handles SomeEvent

    @impl true
    def handle(%SomeEvent{}, _context), do: :ok
  end

  defmodule ReplayAwareReactor do
    use Chronicle.Reactors.Reactor

    @handles SomeEvent
    @receiver_name :reactor_handler_replay_test_receiver

    @impl true
    def handle(%SomeEvent{}, _context), do: :ok

    @impl true
    def on_replay_begin, do: notify(:replay_begin)

    @impl true
    def on_replay_end, do: notify(:replay_end)

    @impl true
    def on_partition_replay_begin(partition), do: notify({:partition_replay_begin, partition})

    @impl true
    def on_partition_replay_end(partition), do: notify({:partition_replay_end, partition})

    defp notify(message) do
      case Process.whereis(@receiver_name) do
        nil -> :ok
        pid -> send(pid, message)
      end
    end
  end

  setup do
    {:ok, lifecycle} = Lifecycle.start_link([])
    test = self()

    establish_fun = fn _state, connection_id ->
      send(test, {:established, connection_id})
      {:ok, :fake_stream, nil}
    end

    {:ok, handler} =
      Handler.start_link(
        module: TestReactor,
        connection: :unused,
        event_store: "test",
        namespace: "Default",
        lifecycle: lifecycle,
        establish_fun: establish_fun
      )

    %{lifecycle: lifecycle, handler: handler}
  end

  test "status redacts the live stream credential and headers", %{handler: handler} do
    secret = "reactor-private-key-#{System.unique_integer([:positive])}"

    stream = %GRPC.Client.Stream{
      channel: %GRPC.Channel{
        cred: GRPC.Credential.new(ssl: [key: {:PrivateKeyInfo, secret}]),
        headers: [{"api-key", "reactor-api-secret"}]
      }
    }

    :sys.replace_state(handler, &%{&1 | stream: stream})
    status = :sys.get_status(handler) |> inspect(limit: :infinity)
    refute status =~ secret
    refute status =~ "reactor-api-secret"
    assert status =~ "open"

    formatted =
      Handler.format_status(%{state: :sys.get_state(handler), message: stream, log: [stream]})
      |> inspect(limit: :infinity)

    refute formatted =~ secret
    refute formatted =~ "reactor-api-secret"
  end

  test "unexpected casts do not expose a stream's credential in crash logs", %{handler: handler} do
    secret = "reactor-stream-secret"
    :sys.replace_state(handler, &%{&1 | stream: %{credential: secret}})
    Process.flag(:trap_exit, true)

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        monitor = Process.monitor(handler)
        GenServer.cast(handler, :unexpected_cast)
        assert_receive {:DOWN, ^monitor, :process, ^handler, _}, 2_000
        Logger.flush()
      end)

    assert log =~ "handle_cast/2"
    refute log =~ secret
  end

  test "does not register on :connected alone", %{lifecycle: lifecycle, handler: handler} do
    Lifecycle.connected(lifecycle, "conn-1")
    _ = Lifecycle.phase(lifecycle)
    refute_receive {:established, _}, 100
    assert :sys.get_state(handler).stream == nil
  end

  test "registers the observation stream on :registered with the connection id", %{
    lifecycle: lifecycle,
    handler: handler
  } do
    Lifecycle.connected(lifecycle, "conn-1")
    Lifecycle.registered(lifecycle)

    assert_receive {:established, "conn-1"}, 1_000
    assert :sys.get_state(handler).stream == :fake_stream
  end

  test "tears the stream down on :disconnected", %{lifecycle: lifecycle, handler: handler} do
    Lifecycle.connected(lifecycle, "conn-1")
    Lifecycle.registered(lifecycle)
    assert_receive {:established, "conn-1"}, 1_000

    Lifecycle.disconnected(lifecycle)
    _ = Lifecycle.phase(lifecycle)
    assert :sys.get_state(handler).stream == nil
  end

  describe "side-effect appending (handle/2 returning {:ok, event_or_events})" do
    test "plain :ok performs no append" do
      state = %{append_fun: fn _op -> flunk("should not append") end}
      assert :ok = Handler.handle_result(:ok, state, "triggering-id")
    end

    test "{:error, reason} passes through without appending" do
      state = %{append_fun: fn _op -> flunk("should not append") end}
      assert {:error, :boom} = Handler.handle_result({:error, :boom}, state, "triggering-id")
    end

    test "a single bare event struct is appended to the triggering event source" do
      test_pid = self()

      state = %{
        append_fun: fn op ->
          send(test_pid, {:append_op, op})
          :ok
        end
      }

      assert :ok =
               Handler.handle_result(
                 {:ok, %SideEffectEvent{value: 1}},
                 state,
                 "triggering-id"
               )

      assert_received {:append_op, {:append, "triggering-id", %SideEffectEvent{value: 1}, []}}
    end

    test "a list of bare event structs is appended atomically to the triggering event source" do
      test_pid = self()

      state = %{
        append_fun: fn op ->
          send(test_pid, {:append_op, op})
          :ok
        end
      }

      events = [%SideEffectEvent{value: 1}, %OtherSideEffectEvent{value: 2}]

      assert :ok = Handler.handle_result({:ok, events}, state, "triggering-id")

      assert_received {:append_op, {:append_many, "triggering-id", ^events}}
    end

    test "an EventForEventSourceId is appended to its own explicit event source" do
      test_pid = self()

      state = %{
        append_fun: fn op ->
          send(test_pid, {:append_op, op})
          :ok
        end
      }

      wrapped = %EventForEventSourceId{
        event_source_id: "other-source",
        event: %SideEffectEvent{value: 1}
      }

      assert :ok = Handler.handle_result({:ok, wrapped}, state, "triggering-id")

      assert_received {:append_op, {:append, "other-source", %SideEffectEvent{value: 1}, []}}
    end

    test "a list of EventForEventSourceId targets each event's own source atomically" do
      test_pid = self()

      state = %{
        append_fun: fn op ->
          send(test_pid, {:append_op, op})
          :ok
        end
      }

      wrapped1 = %EventForEventSourceId{
        event_source_id: "id-1",
        event: %SideEffectEvent{value: 1}
      }

      wrapped2 = %EventForEventSourceId{
        event_source_id: "id-2",
        event: %OtherSideEffectEvent{value: 2}
      }

      assert :ok = Handler.handle_result({:ok, [wrapped1, wrapped2]}, state, "triggering-id")

      assert_received {:append_op, {:append_many_for_event_sources, [^wrapped1, ^wrapped2]}}
    end

    test "a mixed list of bare events and EventForEventSourceId normalizes bare events to the triggering source" do
      test_pid = self()

      state = %{
        append_fun: fn op ->
          send(test_pid, {:append_op, op})
          :ok
        end
      }

      bare = %SideEffectEvent{value: 1}

      wrapped = %EventForEventSourceId{
        event_source_id: "other-source",
        event: %OtherSideEffectEvent{value: 2}
      }

      assert :ok = Handler.handle_result({:ok, [bare, wrapped]}, state, "triggering-id")

      assert_received {:append_op, {:append_many_for_event_sources, [normalized, ^wrapped]}}
      assert %EventForEventSourceId{event_source_id: "triggering-id", event: ^bare} = normalized
    end

    test "a failed side-effect append surfaces as an error" do
      state = %{append_fun: fn _op -> {:error, :append_failed} end}

      assert {:error, :append_failed} =
               Handler.handle_result({:ok, %SideEffectEvent{value: 1}}, state, "triggering-id")
    end
  end

  describe "generation delivery" do
    test "sends Compatibility by default" do
      {:ok, lifecycle} = Lifecycle.start_link([])
      establish_fun = fn _state, _connection_id -> {:ok, :fake_stream, nil} end

      {:ok, handler} =
        Handler.start_link(
          module: TestReactor,
          connection: :unused,
          event_store: "test",
          namespace: "Default",
          lifecycle: lifecycle,
          establish_fun: establish_fun
        )

      assert :sys.get_state(handler).generation_delivery == :compatibility
    end

    test "sends Pinned when the reactor opts in" do
      {:ok, lifecycle} = Lifecycle.start_link([])
      establish_fun = fn _state, _connection_id -> {:ok, :fake_stream, nil} end

      {:ok, handler} =
        Handler.start_link(
          module: PinnedReactor,
          connection: :unused,
          event_store: "test",
          namespace: "Default",
          lifecycle: lifecycle,
          establish_fun: establish_fun
        )

      assert :sys.get_state(handler).generation_delivery == :pinned
    end

    test "applies the client-wide default when the reactor doesn't set its own" do
      {:ok, lifecycle} = Lifecycle.start_link([])
      establish_fun = fn _state, _connection_id -> {:ok, :fake_stream, nil} end

      {:ok, handler} =
        Handler.start_link(
          module: DefaultDeliveryReactor,
          connection: :unused,
          event_store: "test",
          namespace: "Default",
          lifecycle: lifecycle,
          establish_fun: establish_fun,
          event_generation_delivery: :pinned
        )

      assert :sys.get_state(handler).generation_delivery == :pinned
    end

    test "the reactor's own option wins over the client-wide default" do
      {:ok, lifecycle} = Lifecycle.start_link([])
      establish_fun = fn _state, _connection_id -> {:ok, :fake_stream, nil} end

      {:ok, handler} =
        Handler.start_link(
          module: PinnedReactor,
          connection: :unused,
          event_store: "test",
          namespace: "Default",
          lifecycle: lifecycle,
          establish_fun: establish_fun,
          event_generation_delivery: :compatibility
        )

      assert :sys.get_state(handler).generation_delivery == :pinned
    end

    test "a pinned reactor handling two generations of one event type id raises on start" do
      Process.flag(:trap_exit, true)

      assert {:error,
              {%Chronicle.Observers.MultipleGenerationsOfEventTypeInObserver{
                 event_type_id: "some-event"
               }, _stack}} =
               Handler.start_link(
                 module: AmbiguousPinReactor,
                 connection: :unused,
                 event_store: "test",
                 namespace: "Default"
               )
    end

    test "build_registration/2 encodes Pinned" do
      state = %{
        module: PinnedReactor,
        event_store: "store",
        namespace: "ns",
        event_type_map: %{"some-event" => SomeEvent},
        generation_delivery: :pinned
      }

      message = Handler.build_registration(state, "connection-1")
      reactor = message."Content"."Value0"."Reactor"
      assert reactor."GenerationDelivery" == :Pinned
    end

    test "build_registration/2 encodes Compatibility" do
      state = %{
        module: TestReactor,
        event_store: "store",
        namespace: "ns",
        event_type_map: %{"some-event" => SomeEvent},
        generation_delivery: :compatibility
      }

      message = Handler.build_registration(state, "connection-1")
      reactor = message."Content"."Value0"."Reactor"
      assert reactor."GenerationDelivery" == :Compatibility
    end
  end

  describe "replay lifecycle" do
    setup %{lifecycle: lifecycle} do
      Process.register(self(), :reactor_handler_replay_test_receiver)
      establish_fun = fn _state, _connection_id -> {:ok, :fake_stream, nil} end

      {:ok, handler} =
        Handler.start_link(
          module: ReplayAwareReactor,
          connection: :unused,
          event_store: "test",
          namespace: "Default",
          lifecycle: lifecycle,
          establish_fun: establish_fun
        )

      Lifecycle.connected(lifecycle, "conn-1")
      Lifecycle.registered(lifecycle)
      %{handler: handler}
    end

    test "invokes on_replay_begin/0 and on_replay_end/0 without sending a ReactorResult", %{
      handler: handler
    } do
      send(handler, {:event_batch, %{Partition: "", ReplayState: :BeginReplay}})
      assert_receive :replay_begin, 1_000

      send(handler, {:event_batch, %{Partition: "", ReplayState: :EndReplay}})
      assert_receive :replay_end, 1_000
    end

    test "invokes on_partition_replay_begin/1 and on_partition_replay_end/1 with the partition",
         %{
           handler: handler
         } do
      send(handler, {:event_batch, %{Partition: "account-1", ReplayState: :BeginReplayPartition}})
      assert_receive {:partition_replay_begin, "account-1"}, 1_000

      send(handler, {:event_batch, %{Partition: "account-1", ReplayState: :EndReplayPartition}})
      assert_receive {:partition_replay_end, "account-1"}, 1_000
    end
  end

  describe "sending a result fails" do
    setup %{lifecycle: lifecycle} do
      test = self()

      establish_fun = fn _state, connection_id ->
        send(test, {:failing_handler_established, connection_id})
        {:ok, :fake_stream, nil}
      end

      send_fun = fn _stream, _result -> exit({:timeout, {GenServer, :call, []}}) end

      {:ok, handler} =
        Handler.start_link(
          module: TestReactor,
          connection: :unused,
          event_store: "test",
          namespace: "Default",
          lifecycle: lifecycle,
          establish_fun: establish_fun,
          send_fun: send_fun
        )

      Lifecycle.connected(lifecycle, "conn-1")
      Lifecycle.registered(lifecycle)
      assert_receive {:failing_handler_established, "conn-1"}, 1_000
      %{handler: handler}
    end

    test "keeps the handler running and reopens its stream", %{handler: handler} do
      monitor = Process.monitor(handler)

      ExUnit.CaptureLog.capture_log(fn ->
        send(handler, {:event_batch, %{Partition: "account-1", Events: []}})
        _ = :sys.get_state(handler)
      end)

      refute_received {:DOWN, ^monitor, :process, ^handler, _}
      assert :sys.get_state(handler).stream == nil
      assert_receive {:failing_handler_established, "conn-1"}, 3_000
    end
  end
end
