# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Registration.CoordinatorDriftTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Chronicle.Discovery.Drift
  alias Chronicle.Registration.Coordinator

  defp state(detect_fun, policy \\ :warn) do
    %{
      event_store: "store",
      namespace: "Default",
      reactors: [],
      reducers: [],
      projections: [],
      read_models: [],
      drift_policy: policy,
      drift_detect_fun: detect_fun,
      drift_findings: []
    }
  end

  defp counting_detect(result) do
    test = self()

    fn _channel, _report, _opts ->
      send(test, :detected)
      result
    end
  end

  test "runs the check once and does not repeat it on a registration retry" do
    finding = %Drift{
      kind: :reactor,
      id: "r",
      reason: :observer_missing_from_code,
      severity: :info
    }

    state = state(counting_detect({:ok, [finding]}))

    capture_log(fn -> assert :ok = Coordinator.check_drift(:channel, state, []) end)
    assert_received :detected

    state = %{state | drift_findings: [finding]}
    assert :ok = Coordinator.check_drift(:channel, state, [])
    refute_received :detected
    assert Process.get(:chronicle_drift_findings) == [finding]
  end

  test "an exception in the check falls into the policy path: warn logs and continues" do
    state = state(fn _channel, _report, _opts -> raise "kaboom" end)

    log = capture_log(fn -> assert :ok = Coordinator.check_drift(:channel, state, []) end)
    assert log =~ "drift check failed"
  end

  test "an exception in the check stops registration under :fail" do
    state = state(fn _channel, _report, _opts -> raise "kaboom" end, :fail)

    assert {:error, {:artifact_identity_drift_check_failed, {:exception, %RuntimeError{}}}} =
             Coordinator.check_drift(:channel, state, [])
  end

  test "an indeterminate result under :fail is not remembered as clean" do
    state = state(counting_detect({:error, :timeout}), :fail)

    assert {:error, _} = Coordinator.check_drift(:channel, state, [])
    assert {:error, _} = Coordinator.check_drift(:channel, state, [])
    assert_received :detected
    assert_received :detected
  end

  test "logs info findings at info level and warning findings at warning level" do
    info = %Drift{
      kind: :reactor,
      id: "info-one",
      reason: :observer_missing_from_code,
      severity: :info
    }

    warning = %Drift{
      kind: :event_type,
      id: "warn-one",
      reason: :schema_changed_without_generation,
      severity: :warning
    }

    log =
      capture_log([level: :info], fn ->
        Coordinator.check_drift(:channel, state(counting_detect({:ok, [info, warning]})), [])
      end)

    assert log =~ ~r/\[info\].*\[info\] reactor info-one/s
    assert log =~ ~r/\[warning\].*\[warning\] event_type warn-one/s
  end
end
