# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Reactors.HandlerTest do
  use ExUnit.Case, async: true

  alias Chronicle.Connections.Lifecycle
  alias Chronicle.Reactors.Handler

  defmodule SomeEvent do
    use Chronicle.Events.EventType, id: "some-event"
    defstruct [:value]
  end

  defmodule TestReactor do
    use Chronicle.Reactors.Reactor

    @handles SomeEvent

    @impl true
    def handle(%SomeEvent{}, _context), do: :ok
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
end
