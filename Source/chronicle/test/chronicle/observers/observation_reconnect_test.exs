# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Observers.ObservationReconnectTest do
  # Reactors and reducers reopen their observation streams the same way, so every
  # behavior here is specified for both handlers.
  use ExUnit.Case, async: true

  alias Chronicle.Connections.Lifecycle

  @moduletag :capture_log

  @client_is_not_connected "Exception was thrown by handler. ClientIsNotConnected: Client 'conn-1' is not connected."

  defmodule SomeEvent do
    use Chronicle.Events.EventType, id: "observation-reconnect-event"
    defstruct [:amount]
  end

  defmodule SomeReadModel do
    use Chronicle.ReadModels.ReadModel
    defstruct [:total]
  end

  defmodule SomeReactor do
    use Chronicle.Reactors.Reactor

    @handles SomeEvent

    @impl true
    def handle(%SomeEvent{}, _context), do: :ok
  end

  defmodule SomeReducer do
    use Chronicle.Reducers.Reducer, model: SomeReadModel

    @handles SomeEvent

    @impl true
    def reduce(%SomeEvent{} = event, _model, _context), do: %SomeReadModel{total: event.amount}
  end

  @observers [
    {"reactor", Chronicle.Reactors.Handler, SomeReactor,
     {:event_batch, %{Partition: "account-1", Events: []}}},
    {"reducer", Chronicle.Reducers.Handler, SomeReducer,
     {:reduce_operation, %{Partition: "account-1", Events: []}}}
  ]

  # Waits of base 1s and longest 8s; the jitter of 0 lands every wait at the start
  # of its upper half, so the scheduled waits are half the backoff ceiling.
  @observation_reconnect [base_delay: 1_000, max_delay: 8_000, healthy_stream_duration: 30_000]

  for {kind, handler_module, observer, delivery} <- @observers do
    describe "a #{kind} whose observation stream ends" do
      @describetag handler_module: handler_module, observer: observer, delivery: delivery

      setup context do
        start_observer(context.handler_module, context.observer)
      end

      test "reopens it after a jittered wait that grows while streams keep ending", context do
        pid = registered(context)

        {delays, _} =
          Enum.map_reduce(1..5, pid, fn _, pid ->
            delay = stream_ends(context, pid, :closed)
            {delay, reopened(context)}
          end)

        assert delays == [500, 1_000, 2_000, 4_000, 4_000]
      end

      test "backs off when the kernel is unavailable", context do
        pid = registered(context)

        assert stream_ends(context, pid, %GRPC.RPCError{status: 14, message: "unavailable"}) ==
                 500

        pid = reopened(context)

        assert stream_ends(context, pid, %GRPC.RPCError{status: 14, message: "unavailable"}) ==
                 1_000
      end

      test "starts the wait over once a stream delivered", context do
        pid = registered(context)
        assert stream_ends(context, pid, :closed) == 500
        pid = reopened(context)
        assert stream_ends(context, pid, :closed) == 1_000
        pid = reopened(context)

        send(context.handler, context.delivery)

        assert stream_ends(context, pid, :closed) == 500
      end

      test "starts the wait over once a stream stayed open long enough", context do
        pid = registered(context)
        assert stream_ends(context, pid, :closed) == 500
        pid = reopened(context)
        assert stream_ends(context, pid, :closed) == 1_000
        pid = reopened(context)

        Agent.update(context.clock, &(&1 + 30_000))

        assert stream_ends(context, pid, :closed) == 500
      end

      test "reconnects the whole client with a new connection id when the session is lost",
           context do
        pid = registered(context)

        send(
          context.handler,
          {:stream_down, pid, %GRPC.RPCError{status: 2, message: @client_is_not_connected}}
        )

        # The session is asked for a full reconnect for the connection id the kernel refused,
        # and the stream is not reopened with that id.
        assert_receive {:session_lost, "conn-1"}, 1_000
        refute_received {:scheduled, {:reopen, _}, _}
        assert :sys.get_state(context.handler).stream == nil

        # The session drops and comes back with a new connection id; the observer
        # registers again with it.
        Lifecycle.disconnected(context.lifecycle)
        Lifecycle.connected(context.lifecycle, "conn-2")
        Lifecycle.registered(context.lifecycle)

        assert_receive {:established, "conn-2", _}, 1_000
        refute_received {:scheduled, {:reopen, _}, _}
      end

      test "ignores the end of a stream it already replaced", context do
        old = registered(context)
        assert stream_ends(context, old, :closed) == 500
        current = reopened(context)

        send(context.handler, {:stream_down, old, :closed})

        state = :sys.get_state(context.handler)
        assert state.stream == :fake_stream
        assert state.receiver_task.pid == current
        refute_received {:scheduled, {:reopen, _}, _}
      end

      test "ignores a wait that had already ended when the stream was replaced", context do
        pid = registered(context)
        assert stream_ends(context, pid, :closed) == 500
        stale = pending_reopen(context)

        # The session drops and comes back before the handler handles the reopen
        # its ended wait already sent.
        Lifecycle.disconnected(context.lifecycle)
        Lifecycle.connected(context.lifecycle, "conn-2")
        Lifecycle.registered(context.lifecycle)
        assert_receive {:established, "conn-2", current}, 1_000

        send(context.handler, stale)

        state = :sys.get_state(context.handler)
        assert state.stream == :fake_stream
        assert state.receiver_task.pid == current
        refute_received {:established, _, _}
      end

      test "opens the stream on the next registration when its wait ends unregistered",
           context do
        pid = registered(context)
        assert stream_ends(context, pid, :closed) == 500

        # Connected again but not yet registered when the wait ends.
        Lifecycle.connected(context.lifecycle, "conn-1")
        send(context.handler, pending_reopen(context))

        state = :sys.get_state(context.handler)
        assert state.stream == nil
        assert state.reconnect_timer == nil
        refute_received {:established, _, _}

        Lifecycle.registered(context.lifecycle)

        assert_receive {:established, "conn-1", _}, 1_000
        refute_received {:scheduled, {:reopen, _}, _}
      end
    end

    describe "a #{kind} that fails to register" do
      @describetag handler_module: handler_module, observer: observer

      setup context do
        test = self()

        start_observer(context.handler_module, context.observer,
          establish_fun: fn _state, connection_id ->
            send(test, {:establish_failed, connection_id})
            {:error, :unavailable}
          end
        )
      end

      test "waits longer each time registering fails again", context do
        Lifecycle.connected(context.lifecycle, "conn-1")
        Lifecycle.registered(context.lifecycle)

        delays =
          for _ <- 1..4 do
            assert_receive {:establish_failed, "conn-1"}, 1_000
            assert_receive {:scheduled, {:reopen, _} = reopen, delay}, 1_000
            send(context.handler, reopen)
            delay
          end

        assert delays == [500, 1_000, 2_000, 4_000]
      end
    end

    describe "a #{kind} without a lifecycle whose session is lost" do
      @describetag handler_module: handler_module, observer: observer

      setup context do
        start_observer(context.handler_module, context.observer, lifecycle: nil)
      end

      test "reopens its stream after a wait instead of reconnecting the client", context do
        send(context.handler, {:chronicle_lifecycle, :registered, "conn-1"})
        assert_receive {:established, "conn-1", pid}, 1_000

        send(
          context.handler,
          {:stream_down, pid, %GRPC.RPCError{status: 2, message: @client_is_not_connected}}
        )

        assert_receive {:scheduled, {:reopen, _} = reopen, 500}, 1_000
        refute_received {:session_lost, _}

        send(context.handler, reopen)
        assert_receive {:established, "conn-1", _}, 1_000
      end
    end
  end

  describe "the :observation_reconnect client option" do
    test "rejects a mistyped option when the client starts" do
      assert_raise ArgumentError, ~r/max_dealy/, fn ->
        Chronicle.Client.init(client_opts(observation_reconnect: [max_dealy: 5_000]))
      end
    end

    test "rejects a longest wait below the base delay when the client starts" do
      assert_raise ArgumentError, fn ->
        Chronicle.Client.init(
          client_opts(observation_reconnect: [base_delay: 5_000, max_delay: 1_000])
        )
      end
    end

    test "does not take the random source or the clock" do
      assert_raise ArgumentError, fn ->
        Chronicle.Client.init(client_opts(observation_reconnect: [jitter_fun: fn -> 0.0 end]))
      end
    end
  end

  defp client_opts(opts) do
    name = :"observation_reconnect_client_#{System.unique_integer([:positive])}"
    on_exit(fn -> :persistent_term.erase({Chronicle.Client, name}) end)

    [
      name: name,
      discover: false,
      connection_string: "chronicle://u:p@localhost:1",
      drift_policy: :ignore
    ] ++ opts
  end

  defp start_observer(handler_module, observer, overrides \\ []) do
    test = self()
    {:ok, lifecycle} = Lifecycle.start_link([])
    {:ok, clock} = Agent.start_link(fn -> 0 end)

    # Runs in the handler, so the handler owns the stand-in receiver task and can
    # shut it down like a real one.
    establish_fun = fn _state, connection_id ->
      task = Task.async(fn -> Process.sleep(:infinity) end)
      send(test, {:established, connection_id, task.pid})
      {:ok, :fake_stream, task}
    end

    send_after_fun = fn message, delay ->
      send(test, {:scheduled, message, delay})
      make_ref()
    end

    {:ok, handler} =
      handler_module.start_link(
        Keyword.merge(
          [
            module: observer,
            connection: :unused,
            event_store: "test",
            namespace: "Default",
            lifecycle: lifecycle,
            establish_fun: establish_fun,
            send_fun: fn _stream, _result -> :ok end,
            send_after_fun: send_after_fun,
            session_lost_fun: &send(test, {:session_lost, &1}),
            observation_reconnect: @observation_reconnect,
            jitter_fun: fn -> 0.0 end,
            now_fun: fn -> Agent.get(clock, & &1) end
          ],
          overrides
        )
      )

    %{lifecycle: lifecycle, clock: clock, handler: handler}
  end

  defp registered(context) do
    Lifecycle.connected(context.lifecycle, "conn-1")
    Lifecycle.registered(context.lifecycle)
    assert_receive {:established, "conn-1", pid}, 1_000
    pid
  end

  # Ends the stream whose receiver is `pid`, returning the wait scheduled before reopening it.
  defp stream_ends(context, pid, reason) do
    send(context.handler, {:stream_down, pid, reason})
    assert_receive {:scheduled, {:reopen, _}, delay}, 1_000
    delay
  end

  # The message the handler's pending wait sends when it ends.
  defp pending_reopen(context) do
    {_timer, ref} = :sys.get_state(context.handler).reconnect_timer
    {:reopen, ref}
  end

  # Fires the scheduled reopen by hand, returning the new stream's receiver.
  defp reopened(context) do
    send(context.handler, pending_reopen(context))
    assert_receive {:established, "conn-1", pid}, 1_000
    pid
  end
end
