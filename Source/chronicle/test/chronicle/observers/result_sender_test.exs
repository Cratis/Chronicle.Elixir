# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Observers.ResultSenderTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Chronicle.Observers.ResultSender

  @event [:chronicle, :observer, :result, :send_failed]

  setup do
    test = self()
    handler = "result-sender-#{System.unique_integer()}"

    :telemetry.attach(
      handler,
      @event,
      fn _event, measurements, metadata, _ ->
        send(test, {:telemetry, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)
  end

  test "sends the result" do
    test = self()

    assert :ok =
             ResultSender.send_result(:stream, :result, MyReactor, &send(test, {:sent, &1, &2}))

    assert_receive {:sent, :stream, :result}
  end

  test "survives a send that exits, as a timed out call into a busy connection does" do
    log =
      capture_log(fn ->
        assert {:error, {:timeout, _}} =
                 ResultSender.send_result(:stream, :result, MyReactor, fn _, _ ->
                   exit({:timeout, {GenServer, :call, []}})
                 end)
      end)

    assert log =~ "could not send its result"
    assert_receive {:telemetry, %{count: 1}, %{observer: MyReactor}}
  end

  test "survives a send that raises" do
    capture_log(fn ->
      assert {:error, %RuntimeError{}} =
               ResultSender.send_result(:stream, :result, MyReactor, fn _, _ -> raise "gone" end)
    end)
  end
end
