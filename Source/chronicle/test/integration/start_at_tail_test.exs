# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

# Round trip against a real kernel for `start_at_tail: true`. Opt in like the other integration
# tests: point CHRONICLE_INTEGRATION_CONNECTION_STRING at a development kernel and run
# `mix test --include integration`.
#
# Needs a kernel that honors StartAtTail on registration (Chronicle 19.70.0 or later).
defmodule Chronicle.Integration.StartAtTailTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  defmodule SomethingHappened do
    use Chronicle.Events.EventType, id: "sat-something-happened"
    defstruct name: ""
  end

  defmodule TailReactor do
    use Chronicle.Reactors.Reactor, start_at_tail: true

    @handles SomethingHappened

    def handle(%SomethingHappened{name: name}, _context) do
      send(:start_at_tail_it, {:tail, name})
      :ok
    end
  end

  # The control: the same registration without the option catches up on all history.
  defmodule HistoryReactor do
    use Chronicle.Reactors.Reactor

    @handles SomethingHappened

    def handle(%SomethingHappened{name: name}, _context) do
      send(:start_at_tail_it, {:history, name})
      :ok
    end
  end

  setup_all do
    connection_string = System.fetch_env!("CHRONICLE_INTEGRATION_CONNECTION_STRING")
    prefix = System.get_env("CHRONICLE_INTEGRATION_EVENT_STORE_PREFIX", "startattail-elixir")
    event_store = "#{prefix}-#{System.system_time(:millisecond)}-#{System.unique_integer([:positive])}"

    # History exists before either reactor has ever been registered.
    {:ok, _} =
      Chronicle.Client.start_link(
        name: :start_at_tail_writer,
        connection_string: connection_string,
        event_store: event_store,
        discover: false,
        event_types: [SomethingHappened]
      )

    :ok = Chronicle.Client.await_registration(:start_at_tail_writer, 60_000)

    for name <- ["one", "two", "three"] do
      :ok =
        Chronicle.EventSequences.EventLog.append("sat-#{name}", %SomethingHappened{name: name},
          client: :start_at_tail_writer
        )
    end

    {:ok, _} =
      Chronicle.Client.start_link(
        name: :start_at_tail_reader,
        connection_string: connection_string,
        event_store: event_store,
        discover: false,
        event_types: [SomethingHappened],
        reactors: [TailReactor, HistoryReactor]
      )

    :ok = Chronicle.Client.await_registration(:start_at_tail_reader, 60_000)
    :ok
  end

  setup do
    Process.register(self(), :start_at_tail_it)

    on_exit(fn ->
      if Process.whereis(:start_at_tail_it), do: Process.unregister(:start_at_tail_it)
    end)
  end

  test "a reactor marked to start at the tail skips history while an unmarked one catches up on it" do
    # The control proves the history was deliverable, so the silence of the tail reactor is not vacuous.
    for name <- ["one", "two", "three"], do: assert_receive({:history, ^name}, 15_000)

    assert :ok =
             Chronicle.EventSequences.EventLog.append(
               "sat-after",
               %SomethingHappened{name: "after"},
               client: :start_at_tail_reader
             )

    assert_receive {:tail, "after"}, 15_000
    assert_receive {:history, "after"}, 15_000

    refute_received {:tail, "one"}
    refute_received {:tail, "two"}
    refute_received {:tail, "three"}
  end
end
