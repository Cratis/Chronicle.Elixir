# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.ObserversRecoveryTest do
  use ExUnit.Case, async: true

  alias Chronicle.Observers

  defmodule Evt do
    use Chronicle.Events.EventType, id: "recovery-evt"
    defstruct [:v]
  end

  defmodule SomeReactor do
    use Chronicle.Reactors.Reactor, id: "some-reactor-id"
    @handles Evt
    @impl true
    def handle(_e, _c), do: :ok
  end

  test "retry outcomes decode from atoms and numbers" do
    assert Observers.decode_retry_outcome(:Started) == :started
    assert Observers.decode_retry_outcome(:PartitionNotFound) == :partition_not_found
    assert Observers.decode_retry_outcome(:ObserverQuarantined) == :observer_quarantined
    assert Observers.decode_retry_outcome(3) == :partition_quarantined
    assert Observers.decode_retry_outcome(99) == :unknown
  end

  test "clear outcomes decode" do
    assert Observers.decode_clear_outcome(:Cleared) == :cleared
    assert Observers.decode_clear_outcome(:NotFound) == :not_found
    assert Observers.decode_clear_outcome(:NotQuarantined) == :not_quarantined
    assert Observers.decode_clear_outcome(:nope) == :unknown
  end

  test "an observer can be named by id or by its reactor module" do
    assert Observers.observer_id("raw-id") == "raw-id"
    assert Observers.observer_id(SomeReactor) == "some-reactor-id"
    assert_raise ArgumentError, fn -> Observers.observer_id(String) end
  end
end
