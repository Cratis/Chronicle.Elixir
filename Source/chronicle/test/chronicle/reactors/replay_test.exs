# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Reactors.ReplayTest do
  use ExUnit.Case, async: true

  alias Chronicle.Reactors.Handler

  defmodule Charged do
    use Chronicle.Events.EventType, id: "replay-charged"
    defstruct [:amount]
  end

  defmodule Shipped do
    use Chronicle.Events.EventType, id: "replay-shipped"
    defstruct [:id]
  end

  defmodule Plain do
    use Chronicle.Reactors.Reactor
    @handles Charged
    @impl true
    def handle(_event, _context), do: :ok
  end

  defmodule OnceOnlyReactor do
    use Chronicle.Reactors.Reactor, once_only: true
    @handles Charged
    @impl true
    def handle(_event, _context), do: :ok
  end

  defmodule SelectiveReactor do
    use Chronicle.Reactors.Reactor, once_only: [Shipped]
    @handles Charged
    @handles Shipped
    @impl true
    def handle(_event, _context), do: :ok
  end

  defmodule ReplayAware do
    use Chronicle.Reactors.Reactor
    @handles Charged
    @impl true
    def handle(_event, _context), do: :ok
    @impl true
    def handle_replay(_event, _context), do: :ok
  end

  defp state(module) do
    %{
      module: module,
      event_store: "store",
      namespace: "ns",
      event_type_map: %{"replay-charged" => Charged}
    }
  end

  defp definition(module) do
    registration = Handler.build_registration(state(module), %Bcl.Guid{})
    registration |> Map.fetch!(:Content) |> Map.fetch!(:Value0) |> Map.fetch!(:Reactor)
  end

  test "a reactor is replayable by default" do
    definition = definition(Plain)
    assert Map.fetch!(definition, :IsReplayable)
    refute Map.fetch!(definition, :IsNotReplayable)
  end

  test "once_only: true registers the reactor as not replayable" do
    definition = definition(OnceOnlyReactor)
    refute Map.fetch!(definition, :IsReplayable)
    assert Map.fetch!(definition, :IsNotReplayable)
  end

  test "once_only with event types keeps the reactor replayable" do
    definition = definition(SelectiveReactor)
    assert Map.fetch!(definition, :IsReplayable)
    refute Map.fetch!(definition, :IsNotReplayable)
  end

  describe "replay_action/3" do
    test "outside a replay everything is handled normally" do
      for module <- [Plain, OnceOnlyReactor, SelectiveReactor, ReplayAware] do
        assert Handler.replay_action(module, Charged, %{replaying?: false}) == :handle
      end
    end

    test "a once-only reactor never handles a replayed event" do
      assert Handler.replay_action(OnceOnlyReactor, Charged, %{replaying?: true}) == :skip
    end

    test "only the listed events are skipped" do
      assert Handler.replay_action(SelectiveReactor, Shipped, %{replaying?: true}) == :skip
      assert Handler.replay_action(SelectiveReactor, Charged, %{replaying?: true}) == :handle
    end

    test "handle_replay/2 is preferred while replaying" do
      assert Handler.replay_action(ReplayAware, Charged, %{replaying?: true}) == :handle_replay
      assert Handler.replay_action(Plain, Charged, %{replaying?: true}) == :handle
    end
  end
end
