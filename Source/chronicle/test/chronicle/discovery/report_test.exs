# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Discovery.ReportTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Chronicle.Discovery.Report

  defmodule SomeEvent do
    use Chronicle.Events.EventType, id: "some-event"
    defstruct [:value]
  end

  defmodule SomeEventV2 do
    use Chronicle.Events.EventType, id: "some-event", generation: 2
    defstruct [:value, :extra]
  end

  defmodule SomeReadModel do
    use Chronicle.ReadModels.ReadModel
    defstruct [:value]

    from(SomeEvent, set: [value: :value])
  end

  defmodule DefaultedReactor do
    use Chronicle.Reactors.Reactor

    @handles SomeEvent

    @impl true
    def handle(%SomeEvent{}, _context), do: :ok
  end

  defmodule NamedReducer do
    use Chronicle.Reducers.Reducer, id: "named-reducer", model: SomeReadModel

    @handles SomeEvent

    @impl true
    def reduce(%SomeEvent{} = event, _model, _context), do: %SomeReadModel{value: event.value}
  end

  defmodule DeclarativeProjection do
    use Chronicle.Projections.Projection, model: SomeReadModel

    from(SomeEvent, set: [value: :value])
  end

  defmodule StandaloneConstraint do
    use Chronicle.Events.Constraint

    unique name: "UniqueValue" do
      on(SomeEvent, [:value])
    end
  end

  describe "build/1" do
    test "returns not-run-looking empty report when called with no artifacts" do
      report = Report.build()
      assert report.has_run
      assert report.artifacts == []
    end

    test "builds event type artifacts with generation and explicit id_source" do
      report = Report.build(%{event_types: [SomeEvent, SomeEventV2]})

      assert [a, b] = Report.of_kind(report, :event_type)
      assert a.id == "some-event"
      assert a.generation == 1
      assert a.id_source == :explicit
      assert b.generation == 2
    end

    test "builds reactor artifacts, tagging id_source" do
      report = Report.build(%{reactors: [DefaultedReactor], warn_defaulted_ids: false})
      assert [artifact] = Report.of_kind(report, :reactor)
      assert artifact.id == to_string(DefaultedReactor)
      assert artifact.id_source == :module_name
    end

    test "builds reducer artifacts, tagging an explicit id_source" do
      report = Report.build(%{reducers: [NamedReducer], warn_defaulted_ids: false})
      assert [artifact] = Report.of_kind(report, :reducer)
      assert artifact.id == "named-reducer"
      assert artifact.id_source == :explicit
    end

    test "builds declarative projection artifacts" do
      report = Report.build(%{projections: [DeclarativeProjection], warn_defaulted_ids: false})
      assert [artifact] = Report.of_kind(report, :projection)
      assert artifact.id == "DeclarativeProjection"
      assert artifact.id_source == :module_name
    end

    test "builds read model artifacts" do
      report = Report.build(%{read_models: [SomeReadModel]})
      assert [artifact] = Report.of_kind(report, :read_model)
      assert artifact.id == "SomeReadModel"
    end

    test "builds one artifact per constraint definition name" do
      report = Report.build(%{constraints: [StandaloneConstraint]})
      assert [artifact] = Report.of_kind(report, :constraint)
      assert artifact.id == "UniqueValue"
      assert artifact.id_source == :explicit
    end

    test "counts and summary cover every artifact kind" do
      report = Report.build(%{event_types: [SomeEvent], reducers: [NamedReducer]})
      assert Report.count_of(report, :event_type) == 1
      assert Report.count_of(report, :reducer) == 1
      assert Report.count_of(report, :reactor) == 0
      assert Report.summary(report) =~ "1 event types"
      assert Report.summary(report) =~ "1 reducers"
    end

    test "format/1 renders every kind, even when empty" do
      report = Report.build(%{event_types: [SomeEvent]})
      rendered = Report.format(report)
      assert rendered =~ "event types (1): some-event"
      assert rendered =~ "reactors (0)"
    end

    test "not_run/0 reports has_run false and formats distinctly" do
      report = Report.not_run()
      refute report.has_run
      assert report.artifacts == []
      assert Report.format(report) =~ "not run"
      assert Report.summary(report) == "not run"
    end
  end

  describe "defaulted id warning" do
    test "warns once per module even across repeated report builds" do
      defmodule WarnOnceReactor do
        use Chronicle.Reactors.Reactor

        @handles Chronicle.Discovery.ReportTest.SomeEvent

        @impl true
        def handle(%Chronicle.Discovery.ReportTest.SomeEvent{}, _context), do: :ok
      end

      log =
        capture_log(fn ->
          Report.build(%{reactors: [WarnOnceReactor]})
          Report.build(%{reactors: [WarnOnceReactor]})
        end)

      assert Regex.scan(~r/has no explicit :id/, log) |> length() == 1
    end

    test "warn_defaulted_ids: false suppresses the warning" do
      defmodule SuppressedReactor do
        use Chronicle.Reactors.Reactor

        @handles Chronicle.Discovery.ReportTest.SomeEvent

        @impl true
        def handle(%Chronicle.Discovery.ReportTest.SomeEvent{}, _context), do: :ok
      end

      log =
        capture_log(fn ->
          Report.build(%{reactors: [SuppressedReactor], warn_defaulted_ids: false})
        end)

      refute log =~ "has no explicit :id"
    end

    test "an explicit id never warns" do
      log =
        capture_log(fn ->
          Report.build(%{reducers: [NamedReducer]})
        end)

      refute log =~ "has no explicit :id"
    end
  end
end
