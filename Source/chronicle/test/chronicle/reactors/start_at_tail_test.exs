# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Reactors.StartAtTailTest do
  use ExUnit.Case, async: true

  alias Chronicle.Reactors.Handler

  defmodule Charged do
    use Chronicle.Events.EventType, id: "start-at-tail-charged"
    defstruct [:amount]
  end

  defmodule FromTheBeginning do
    use Chronicle.Reactors.Reactor
    @handles Charged
    @impl true
    def handle(_event, _context), do: :ok
  end

  defmodule FromTheTail do
    use Chronicle.Reactors.Reactor, start_at_tail: true
    @handles Charged
    @impl true
    def handle(_event, _context), do: :ok
  end

  defmodule FromTheTailAndOnceOnly do
    use Chronicle.Reactors.Reactor, start_at_tail: true, once_only: true
    @handles Charged
    @impl true
    def handle(_event, _context), do: :ok
  end

  defp definition(module) do
    state = %{
      module: module,
      event_store: "store",
      namespace: "ns",
      event_type_map: %{"start-at-tail-charged" => Charged},
      generation_delivery: :compatibility
    }

    Handler.build_registration(state, %Bcl.Guid{})
    |> Map.fetch!(:Content)
    |> Map.fetch!(:Value0)
    |> Map.fetch!(:Reactor)
  end

  test "a reactor starts from the beginning by default" do
    refute FromTheBeginning.__chronicle_reactor__(:start_at_tail)
    refute Map.fetch!(definition(FromTheBeginning), :StartAtTail)
  end

  test "start_at_tail: true asks the kernel to begin at the tail" do
    assert FromTheTail.__chronicle_reactor__(:start_at_tail)
    assert Map.fetch!(definition(FromTheTail), :StartAtTail)
  end

  test "start_at_tail leaves the reactor replayable" do
    refute Map.fetch!(definition(FromTheTail), :IsNotReplayable)
  end

  test "start_at_tail composes with once_only" do
    definition = definition(FromTheTailAndOnceOnly)
    assert Map.fetch!(definition, :StartAtTail)
    assert Map.fetch!(definition, :IsNotReplayable)
  end
end
