# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Cratis.Chronicle.Connections.KeepAliveTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Cratis.Chronicle.Connections.KeepAlive

  defp answering(test_pid, result \\ :ok) do
    fn channel, connection_id ->
      send(test_pid, {:answered, channel, connection_id})
      result
    end
  end

  test "answers every keepalive the kernel pushes" do
    stream = [{:ok, :keepalive}, {:ok, :keepalive}, {:ok, :keepalive}]

    KeepAlive.run(self(), stream, :channel, "conn-1", answering(self()))

    # Without one answer per keepalive the kernel's LastSeen goes stale and the
    # client is evicted while the stream stays open — the reported bug.
    assert_receive {:answered, :channel, "conn-1"}
    assert_receive {:answered, :channel, "conn-1"}
    assert_receive {:answered, :channel, "conn-1"}
  end

  test "reports liveness to the handler for every keepalive" do
    stream = [{:ok, :keepalive}, {:ok, :keepalive}]

    KeepAlive.run(self(), stream, :channel, "conn-1", answering(self()))

    assert_receive :keepalive_received
    assert_receive :keepalive_received
  end

  test "reports the session as down when the stream errors" do
    stream = [{:ok, :keepalive}, {:error, :unavailable}]

    KeepAlive.run(self(), stream, :channel, "conn-1", answering(self()))

    assert_receive {:session_down, :unavailable}
  end

  test "reports the session as down when the stream ends" do
    KeepAlive.run(self(), [{:ok, :keepalive}], :channel, "conn-1", answering(self()))

    assert_receive {:session_down, :stream_ended}
  end

  test "stops answering and reports down when an answer fails" do
    stream = [{:ok, :keepalive}, {:ok, :keepalive}, {:ok, :keepalive}]

    KeepAlive.run(self(), stream, :channel, "conn-1", answering(self(), {:error, :boom}))

    assert_receive {:answered, :channel, "conn-1"}
    assert_receive {:session_down, {:keepalive_failed, :boom}}
    # A failing answer means the session is already lost; continuing to consume
    # the stream would keep it looking alive.
    refute_receive {:answered, :channel, "conn-1"}, 100
  end

  describe "the status the kernel reports" do
    defp run_with(statuses) do
      stream = Enum.map(statuses, &{:ok, %{Status: &1}})

      capture_log([level: :info], fn ->
        KeepAlive.run(self(), stream, :channel, "c", answering(self()))
      end)
    end

    test "is quiet while the kernel is accepting" do
      assert run_with([:Accepting, :Accepting]) == ""
    end

    test "reads a keepalive without a status as accepting" do
      log =
        capture_log([level: :info], fn ->
          KeepAlive.run(self(), [{:ok, %{}}, {:ok, :keepalive}], :channel, "c", answering(self()))
        end)

      assert log == ""
    end

    test "warns once when the kernel becomes busy, however many keepalives say so" do
      log = run_with([:Accepting, :Degraded, :Degraded, :Degraded])

      assert length(String.split(log, "reports that it is busy")) == 2
    end

    test "warns when the kernel is recovering" do
      assert run_with([:Recovering]) =~ "recovering"
    end

    test "says when the kernel accepts calls normally again" do
      log = run_with([:Degraded, :Accepting])

      assert log =~ "reports that it is busy"
      assert log =~ "accepting calls normally again"
    end

    test "does not crash on a status it does not know" do
      assert run_with([99]) =~ "status this client does not know"
    end

    test "still answers every keepalive" do
      run_with([:Degraded, :Recovering])

      assert_receive {:answered, :channel, "c"}
      assert_receive {:answered, :channel, "c"}
    end
  end
end
