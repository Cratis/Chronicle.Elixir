# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Registration.RetryPolicyTest do
  use ExUnit.Case, async: true

  alias Chronicle.Registration.RetryPolicy

  test "the default policy keeps the historical fixed five second delay" do
    policy = RetryPolicy.new(nil)
    assert Enum.map(1..4, &RetryPolicy.delay(policy, &1)) == [5_000, 5_000, 5_000, 5_000]
  end

  test "delays grow exponentially up to the cap" do
    policy = RetryPolicy.new(initial_delay: 1_000, max_delay: 10_000)

    assert Enum.map(1..6, &RetryPolicy.delay(policy, &1)) == [
             1_000,
             2_000,
             4_000,
             8_000,
             10_000,
             10_000
           ]
  end

  test "jitter spreads the delay symmetrically around the base" do
    policy = RetryPolicy.new(initial_delay: 1_000, max_delay: 1_000, jitter: 0.5)
    assert RetryPolicy.delay(policy, 1, fn -> 0.0 end) == 500
    assert RetryPolicy.delay(policy, 1, fn -> 0.5 end) == 1_000
    assert RetryPolicy.delay(policy, 1, fn -> 1.0 end) == 1_500
  end

  test "max attempts stops retrying" do
    policy = RetryPolicy.new(max_attempts: 3)
    assert RetryPolicy.retry?(policy, 1, :boom)
    assert RetryPolicy.retry?(policy, 2, :boom)
    refute RetryPolicy.retry?(policy, 3, :boom)
    assert RetryPolicy.retry?(RetryPolicy.new(nil), 1_000, :boom)
  end

  test "failures that cannot succeed are not retried" do
    refute RetryPolicy.retryable?({:validation_results, [%{}]})
    refute RetryPolicy.retryable?(%GRPC.RPCError{status: 3, message: "invalid"})
    assert RetryPolicy.retryable?(%GRPC.RPCError{status: 14, message: "unavailable"})
    assert RetryPolicy.retryable?(:boom)
    refute RetryPolicy.retry?(RetryPolicy.new(nil), 1, {:validation_results, []})
  end
end
