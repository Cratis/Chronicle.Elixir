# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.EventSequences.ConcurrencyWireTest do
  use Chronicle.AppendWireCase

  alias Chronicle.Events.ConcurrencyScope

  defp take_append_request do
    case take_request() do
      %Wire.TailSequenceNumberRequest{} -> take_append_request()
      request -> request
    end
  end

  describe "explicit scope on the wire" do
    test "expecting_no_matching_event sends the explicit guard", %{opts: opts} do
      scope = ConcurrencyScope.expecting_no_matching_event(event_source_id: true)

      assert :ok = append(:single, opts ++ [concurrency_scope: scope])

      assert %Wire.AppendRequest{ConcurrencyScope: %{ExpectsNoMatchingEvent: true}} =
               take_request()
    end

    test "none sends no guard and the unset sequence number", %{opts: opts} do
      assert :ok = append(:single, opts ++ [concurrency_scope: ConcurrencyScope.none()])

      assert %Wire.AppendRequest{
               ConcurrencyScope: %{
                 ExpectsNoMatchingEvent: false,
                 SequenceNumber: 18_446_744_073_709_551_615
               }
             } = take_request()
    end
  end

  describe "default strategy: :none (unchanged behavior)" do
    test "a plain append with no explicit scope sends no concurrency scope", %{opts: opts} do
      assert :ok = append(:single, opts)
      assert %Wire.AppendRequest{ConcurrencyScope: nil} = take_request()
    end
  end

  describe "default strategy: :optimistic" do
    setup %{opts: opts} do
      [client: client] = opts
      config = Chronicle.Client.config(client)

      :persistent_term.put(
        {Chronicle.Client, client},
        Map.put(config, :concurrency, default: :optimistic)
      )

      :ok
    end

    test "reads the tail and expects it unchanged", %{opts: opts} do
      put_response(:tail_sequence_number, 7)

      assert :ok = append(:single, opts)

      assert %Wire.AppendRequest{
               ConcurrencyScope: %{SequenceNumber: 7, EventSourceId: true}
             } = take_append_request()
    end

    test "an explicit scope still wins over the default strategy", %{opts: opts} do
      put_response(:tail_sequence_number, 7)
      scope = ConcurrencyScope.for_event_source(99)

      assert :ok = append(:single, opts ++ [concurrency_scope: scope])

      assert %Wire.AppendRequest{ConcurrencyScope: %{SequenceNumber: 99}} = take_request()
    end

    test "an empty narrowing (first append) sends no guard by default", %{opts: opts} do
      put_response(:tail_sequence_number, 18_446_744_073_709_551_615)

      assert :ok = append(:single, opts)

      assert %Wire.AppendRequest{ConcurrencyScope: nil} = take_append_request()
    end
  end

  describe "default strategy: :optimistic with check_first_append" do
    setup %{opts: opts} do
      [client: client] = opts
      config = Chronicle.Client.config(client)

      :persistent_term.put(
        {Chronicle.Client, client},
        Map.put(config, :concurrency, default: :optimistic, check_first_append: true)
      )

      :ok
    end

    test "an empty narrowing expects no matching event", %{opts: opts} do
      put_response(:tail_sequence_number, 18_446_744_073_709_551_615)

      assert :ok = append(:single, opts)

      assert %Wire.AppendRequest{ConcurrencyScope: %{ExpectsNoMatchingEvent: true}} =
               take_append_request()
    end
  end
end
