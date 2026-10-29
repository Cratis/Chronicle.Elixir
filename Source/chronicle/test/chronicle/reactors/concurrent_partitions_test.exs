# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Reactors.ConcurrentPartitionsTest do
  use ExUnit.Case, async: false

  alias Chronicle.Connections.Lifecycle
  alias Chronicle.Reactors.Handler

  defmodule Started do
    use Chronicle.Events.EventType, id: "concurrent-partitions-started"
    defstruct [:value]
  end

  defmodule BlockingReactor do
    use Chronicle.Reactors.Reactor

    @handles Started

    @impl true
    def handle(%Started{value: value}, context) do
      test = :persistent_term.get({__MODULE__, :test})
      send(test, {:handling, context.event_source_id, value, self()})

      receive do
        :continue -> :ok
      end
    end
  end

  setup do
    :persistent_term.put({BlockingReactor, :test}, self())
    {:ok, lifecycle} = Lifecycle.start_link([])
    test = self()

    {:ok, handler} =
      Handler.start_link(
        module: BlockingReactor,
        connection: :unused,
        event_store: "test",
        namespace: "Default",
        lifecycle: lifecycle,
        max_concurrent_partitions: 2,
        establish_fun: fn _state, _connection_id -> {:ok, :fake_stream, nil} end,
        send_fun: fn _stream, result -> send(test, {:sent, result}) end
      )

    Lifecycle.connected(lifecycle, "conn-1")
    Lifecycle.registered(lifecycle)
    _ = :sys.get_state(handler)
    %{handler: handler}
  end

  defp batch(partition, value, opts \\ []) do
    %{
      Partition: partition,
      DeliveryId: Keyword.get(opts, :delivery_id, 0),
      DeliverWithinMilliseconds: Keyword.get(opts, :within, 0),
      Events: [
        %{
          Context: %{
            EventType: %{Id: "concurrent-partitions-started", Generation: 1},
            EventSourceId: partition,
            SequenceNumber: value
          },
          Content: Jason.encode!(%{value: value})
        }
      ]
    }
  end

  defp result(message), do: Map.fetch!(Map.fetch!(message, :Content), :Value1)

  test "handles different partitions at the same time", %{handler: handler} do
    send(handler, {:event_batch, batch("a", 1)})
    send(handler, {:event_batch, batch("b", 2)})

    assert_receive {:handling, "a", 1, worker_a}, 1_000
    assert_receive {:handling, "b", 2, worker_b}, 1_000

    send(worker_a, :continue)
    send(worker_b, :continue)
    assert_receive {:sent, _}, 1_000
    assert_receive {:sent, _}, 1_000
  end

  test "handles one partition's batches one at a time and in order", %{handler: handler} do
    send(handler, {:event_batch, batch("a", 1)})
    send(handler, {:event_batch, batch("a", 2)})

    assert_receive {:handling, "a", 1, worker}, 1_000
    refute_receive {:handling, "a", 2, _}, 100

    send(worker, :continue)
    assert_receive {:sent, _}, 1_000
    assert_receive {:handling, "a", 2, worker}, 1_000
    send(worker, :continue)
    assert_receive {:sent, _}, 1_000
  end

  test "does not handle more partitions at once than allowed", %{handler: handler} do
    for partition <- ["a", "b", "c"], do: send(handler, {:event_batch, batch(partition, 1)})

    assert_receive {:handling, _, 1, first}, 1_000
    assert_receive {:handling, _, 1, second}, 1_000
    refute_receive {:handling, _, 1, _}, 100

    send(first, :continue)
    assert_receive {:handling, _, 1, third}, 1_000
    send(second, :continue)
    send(third, :continue)
  end

  test "stays responsive while batches run", %{handler: handler} do
    send(handler, {:event_batch, batch("a", 1)})
    assert_receive {:handling, "a", 1, worker}, 1_000

    assert %{stream: :fake_stream} = :sys.get_state(handler)
    send(worker, :continue)
  end

  test "echoes the delivery id", %{handler: handler} do
    send(handler, {:event_batch, batch("a", 1, delivery_id: 42)})
    assert_receive {:handling, "a", 1, worker}, 1_000
    send(worker, :continue)

    assert_receive {:sent, message}, 1_000
    assert Map.fetch!(result(message), :DeliveryId) == 42
  end

  test "answers a delivery the kernel already gave up on without handling it", %{handler: handler} do
    test = self()
    telemetry = "expired-#{System.unique_integer()}"

    :telemetry.attach(
      telemetry,
      [:chronicle, :observer, :batch, :expired],
      fn _, measurements, _, _ -> send(test, {:expired, measurements}) end,
      nil
    )

    on_exit(fn -> :telemetry.detach(telemetry) end)

    received_at = System.monotonic_time(:millisecond) - 5_000
    send(handler, {:event_batch, batch("a", 1, within: 1_000, delivery_id: 7), received_at})

    assert_receive {:sent, message}, 1_000
    refute_received {:handling, _, _, _}
    assert Map.fetch!(result(message), :State) == 2
    assert Map.fetch!(result(message), :DeliveryId) == 7
    assert [reason] = Map.fetch!(result(message), :ExceptionMessages)
    assert reason =~ "expired"
    assert_receive {:expired, %{waited: waited}}
    assert waited >= 5_000
  end

  test "handles a delivery that is still within its deadline", %{handler: handler} do
    send(handler, {:event_batch, batch("a", 1, within: 60_000)})
    assert_receive {:handling, "a", 1, worker}, 1_000
    send(worker, :continue)
    assert_receive {:sent, message}, 1_000
    assert Map.fetch!(result(message), :State) == 1
  end
end
