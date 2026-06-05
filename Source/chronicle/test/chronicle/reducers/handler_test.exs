# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Reducers.HandlerTest do
  use ExUnit.Case, async: true

  alias Chronicle.Connections.Lifecycle
  alias Chronicle.Reducers.Handler

  defmodule MyEvent do
    use Chronicle.Events.EventType, id: "my-event"
    defstruct [:amount]
  end

  defmodule MyReadModel do
    use Chronicle.ReadModels.ReadModel
    defstruct [:total]
  end

  defmodule TestReducer do
    use Chronicle.Reducers.Reducer, model: MyReadModel

    @handles MyEvent

    @impl true
    def reduce(%MyEvent{} = event, nil, _context), do: %MyReadModel{total: event.amount}

    def reduce(%MyEvent{} = event, model, _context),
      do: %{model | total: model.total + event.amount}
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
        module: TestReducer,
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

  test "re-registers with a fresh connection id after reconnect", %{lifecycle: lifecycle} do
    Lifecycle.connected(lifecycle, "conn-1")
    Lifecycle.registered(lifecycle)
    assert_receive {:established, "conn-1"}, 1_000

    Lifecycle.disconnected(lifecycle)
    Lifecycle.connected(lifecycle, "conn-2")
    Lifecycle.registered(lifecycle)
    assert_receive {:established, "conn-2"}, 1_000
  end
end
