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
end
