# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Seeding.RunnerTest do
  use ExUnit.Case, async: true

  alias Chronicle.Connections.Lifecycle
  alias Chronicle.Seeding.Runner

  defmodule SomeEvent do
    use Chronicle.Events.EventType, id: "some-event"
    defstruct [:value]
  end

  defmodule TestSeeder do
    use Chronicle.Seeding.Seeder

    @impl true
    def seed(builder) do
      Chronicle.Seeding.for(builder, SomeEvent, "source-1", [%SomeEvent{value: "seeded"}])
    end
  end

  defp start_runner(lifecycle, opts) do
    {:ok, pid} =
      Runner.start_link(
        [
          client: :test,
          connection: :unused,
          event_store: "test",
          namespace: "default",
          lifecycle: lifecycle,
          seeders: [TestSeeder]
        ] ++ opts
      )

    pid
  end

  test "runs seeders on the :registered phase" do
    {:ok, lifecycle} = Lifecycle.start_link([])
    test = self()

    start_runner(lifecycle,
      has_events_for: fn _id, _opts -> {:ok, false} end,
      append_many: fn id, events, _opts ->
        send(test, {:appended, id, events})
        :ok
      end
    )

    Lifecycle.connected(lifecycle, "conn-1")
    Lifecycle.registered(lifecycle)

    assert_receive {:appended, "source-1", [%SomeEvent{value: "seeded"}]}, 1_000
  end

  test "does not append when the event source already has events" do
    {:ok, lifecycle} = Lifecycle.start_link([])
    test = self()

    runner =
      start_runner(lifecycle,
        has_events_for: fn _id, _opts -> {:ok, true} end,
        append_many: fn id, events, _opts ->
          send(test, {:appended, id, events})
          :ok
        end
      )

    Lifecycle.connected(lifecycle, "conn-1")
    Lifecycle.registered(lifecycle)

    refute_receive {:appended, _, _}, 200
    assert Process.alive?(runner)
  end

  test "survives an append failure and stays alive to retry" do
    {:ok, lifecycle} = Lifecycle.start_link([])
    test = self()

    runner =
      start_runner(lifecycle,
        has_events_for: fn _id, _opts -> {:ok, false} end,
        append_many: fn id, _events, _opts ->
          send(test, {:attempted, id})
          {:error, :boom}
        end
      )

    Lifecycle.connected(lifecycle, "conn-1")
    Lifecycle.registered(lifecycle)

    assert_receive {:attempted, "source-1"}, 1_000
    assert Process.alive?(runner)
  end
end
