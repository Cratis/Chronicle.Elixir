# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Observers.ReconnectBackoffTest do
  use ExUnit.Case, async: true

  alias Chronicle.Observers.ReconnectBackoff

  # A clock the test moves by hand, read through the backoff's now_fun.
  defp clock do
    {:ok, clock} = Agent.start_link(fn -> 0 end)
    clock
  end

  defp advance(clock, milliseconds), do: Agent.update(clock, &(&1 + milliseconds))

  defp backoff(options) do
    clock = Keyword.get_lazy(options, :clock, &clock/0)

    ReconnectBackoff.new(
      [
        base_delay: Keyword.get(options, :base_delay, 1_000),
        max_delay: Keyword.get(options, :max_delay, 8_000),
        healthy_stream_duration: Keyword.get(options, :healthy_stream_duration, 30_000)
      ],
      jitter_fun: fn -> Keyword.get(options, :jitter, 1.0) end,
      now_fun: fn -> Agent.get(clock, & &1) end
    )
  end

  # Opens a stream that ends straight away, returning the wait before the next one.
  defp end_stream_without_working(backoff) do
    backoff |> ReconnectBackoff.stream_opened() |> ReconnectBackoff.next_delay()
  end

  defp delays(backoff, count) do
    {delays, backoff} =
      Enum.map_reduce(1..count, backoff, fn _, backoff -> end_stream_without_working(backoff) end)

    {delays, backoff}
  end

  describe "when streams keep ending without working" do
    test "doubles the wait up to the longest wait" do
      {delays, _} = delays(backoff([]), 6)

      assert delays == [1_000, 2_000, 4_000, 8_000, 8_000, 8_000]
    end

    test "never overflows however often streams end" do
      {delays, _} = delays(backoff(max_delay: 60_000), 100)

      assert List.last(delays) == 60_000
    end
  end

  describe "when jittering the wait" do
    test "lands at the start of the upper half for the lowest jitter" do
      assert {500, _} = end_stream_without_working(backoff(jitter: 0.0))
    end

    test "lands in the middle of the upper half" do
      assert {750, _} = end_stream_without_working(backoff(jitter: 0.5))
    end

    test "keeps a jitter outside [0, 1] within the upper half" do
      assert {500, _} = end_stream_without_working(backoff(jitter: -3.0))
      assert {1_000, _} = end_stream_without_working(backoff(jitter: 7.0))
    end

    test "uses a random jitter by default" do
      backoff = ReconnectBackoff.new(base_delay: 1_000)

      {delays, _} =
        Enum.map_reduce(1..20, backoff, fn _, _ -> ReconnectBackoff.next_delay(backoff) end)

      assert Enum.all?(delays, &(&1 in 500..1_000))
    end
  end

  describe "when a stream delivered before it ended" do
    test "starts over at the base delay" do
      {_, backoff} = delays(backoff([]), 3)

      {delay, _} =
        backoff
        |> ReconnectBackoff.stream_opened()
        |> ReconnectBackoff.stream_delivered()
        |> ReconnectBackoff.next_delay()

      assert delay == 1_000
    end
  end

  describe "when a stream stayed open long enough before it ended" do
    test "starts over at the base delay" do
      clock = clock()
      {_, backoff} = delays(backoff(clock: clock), 3)

      backoff = ReconnectBackoff.stream_opened(backoff)
      advance(clock, 30_000)

      assert {1_000, _} = ReconnectBackoff.next_delay(backoff)
    end

    test "keeps growing for a stream that ended just short of it" do
      clock = clock()
      {_, backoff} = delays(backoff(clock: clock), 3)

      backoff = ReconnectBackoff.stream_opened(backoff)
      advance(clock, 29_999)

      assert {8_000, _} = ReconnectBackoff.next_delay(backoff)
    end
  end

  describe "when the base delay is zero" do
    test "reopens at once however often streams end" do
      {delays, _} = delays(backoff(base_delay: 0), 5)

      assert delays == [0, 0, 0, 0, 0]
    end
  end

  describe "options" do
    test "default to the .NET client's waits" do
      backoff = ReconnectBackoff.new()

      assert backoff.base_delay == 2_000
      assert backoff.max_delay == 60_000
      assert backoff.healthy_stream_duration == 180_000
    end

    test "reject an unknown option" do
      assert_raise ArgumentError, fn -> ReconnectBackoff.new(base_dely: 1_000) end
    end

    test "reject a wait that is not a non-negative integer of milliseconds" do
      assert_raise ArgumentError, fn -> ReconnectBackoff.new(max_delay: -1) end
      assert_raise ArgumentError, fn -> ReconnectBackoff.new(base_delay: 1.5) end
    end

    test "reject a longest wait below the base delay" do
      assert_raise ArgumentError, fn ->
        ReconnectBackoff.new(base_delay: 5_000, max_delay: 1_000)
      end
    end

    test "accept a longest wait equal to the base delay" do
      assert {1_000, _} =
               [base_delay: 2_000, max_delay: 2_000]
               |> ReconnectBackoff.new(jitter_fun: fn -> 0.0 end)
               |> ReconnectBackoff.next_delay()
    end

    test "do not take the random source or the clock" do
      assert_raise ArgumentError, fn -> ReconnectBackoff.new(jitter_fun: fn -> 0.0 end) end
      assert_raise ArgumentError, fn -> ReconnectBackoff.new(now_fun: fn -> 0 end) end
    end
  end
end
