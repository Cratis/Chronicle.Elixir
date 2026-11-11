# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Observers.StreamErrorsTest do
  use ExUnit.Case, async: true

  alias Chronicle.Observers.StreamErrors

  @client_is_not_connected "Exception was thrown by handler. ClientIsNotConnected: Client 'abc' is not connected."

  test "a refused connection id is a lost session" do
    error = %GRPC.RPCError{status: 2, message: @client_is_not_connected}

    assert StreamErrors.classify(error) == :session_lost
  end

  test "a lost session wrapped in an error tuple is still a lost session" do
    error = %GRPC.RPCError{status: 2, message: @client_is_not_connected}

    assert StreamErrors.classify({:error, error}) == :session_lost
  end

  test "an unavailable kernel is a lost connection" do
    assert StreamErrors.classify(%GRPC.RPCError{status: 14, message: "unavailable"}) ==
             :connection_lost
  end

  test "a cancelled stream is cancelled" do
    assert StreamErrors.classify(%GRPC.RPCError{status: 1, message: "cancelled"}) == :cancelled
  end

  test "any other gRPC error is a failure" do
    assert StreamErrors.classify(%GRPC.RPCError{status: 13, message: "internal"}) == :failure
  end

  test "a reason that is not a gRPC error is a failure" do
    assert StreamErrors.classify(:normal) == :failure
    assert StreamErrors.classify(:closed) == :failure
  end
end
