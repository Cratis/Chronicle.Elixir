# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Cratis.Chronicle.Observers.Multiplexed.ChannelTest do
  use ExUnit.Case, async: true

  alias Cratis.Chronicle.Observers.Multiplexed.{Channel, ObserverStream}
  alias Cratis.Chronicle.Contracts.Observation.Multiplexed, as: Wire
  alias Cratis.Chronicle.Contracts.Observation.Reactors
  alias Cratis.Chronicle.Contracts.Observation.Reducers

  @capability "multiplexed-observation"

  # The channel is driven through its seams: the shared call is a fake whose writes the test sees
  # and whose replies the test feeds from the process that reads them.
  defp start_channel(opts \\ []) do
    test = self()
    calls = :counters.new(1, [])

    defaults = [
      flush_interval: 5,
      capabilities_fun: fn _channel -> {:ok, [@capability]} end,
      open_fun: fn _channel ->
        :counters.add(calls, 1, 1)
        {:ok, {:call, :counters.get(calls, 1)}, []}
      end,
      send_fun: fn call, message -> send(test, {:wrote, call, message}) end,
      recv_fun: fn call ->
        send(test, {:reader, call, self()})
        {:ok, replies()}
      end,
      end_fun: fn call -> send(test, {:ended, call}) end
    ]

    pid = start_supervised!({Channel, Keyword.merge(defaults, opts)})
    %{channel: pid, calls: calls}
  end

  # The replies the kernel feeds the process that reads them, until it ends or fails the call.
  defp replies do
    Stream.unfold(:running, fn
      :stopped ->
        nil

      :running ->
        receive do
          {:kernel, message} -> {{:ok, message}, :running}
          {:kernel_fails, reason} -> {{:error, reason}, :stopped}
          :kernel_ends -> nil
        end
    end)
  end

  defp reactor_registration(id \\ "reactor") do
    %Reactors.ReactorMessage{
      Content: %Reactors.OneOf_RegisterReactor_ReactorResult{
        Value0: %Reactors.RegisterReactor{ConnectionId: id}
      }
    }
  end

  defp reactor_result(delivery_id) do
    %Reactors.ReactorMessage{
      Content: %Reactors.OneOf_RegisterReactor_ReactorResult{
        Value1: %Reactors.ReactorResult{DeliveryId: delivery_id}
      }
    }
  end

  defp reducer_registration do
    %Reducers.ReducerMessage{
      Content: %Reducers.OneOf_RegisterReducer_ReducerResult{
        Value0: %Reducers.RegisterReducer{ConnectionId: "reducer"}
      }
    }
  end

  defp delivery(stream_id, sequence, partition) do
    %Wire.MultiplexedServerMessage{
      StreamId: stream_id,
      Sequence: sequence,
      Reactor: %Wire.EventsToObserve{Partition: partition}
    }
  end

  defp open!(channel, kind \\ :reactor, registration \\ reactor_registration()) do
    assert {:ok, %ObserverStream{} = stream} = Channel.open(channel, :grpc, kind, registration)
    stream
  end

  defp reader! do
    assert_receive {:reader, _call, reader}, 500
    reader
  end

  defp feed(reader, message), do: send(reader, {:kernel, message})

  describe "choosing between one call per observer and one for the connection" do
    test "uses the shared call when the kernel advertises the capability" do
      %{channel: channel} = start_channel()

      assert {:ok, %ObserverStream{kind: :reactor}} =
               Channel.open(channel, :grpc, :reactor, reactor_registration())
    end

    test "leaves the observer to its own call when the kernel does not advertise it" do
      %{channel: channel, calls: calls} =
        start_channel(capabilities_fun: fn _ -> {:ok, ["something-else"]} end)

      assert :unsupported = Channel.open(channel, :grpc, :reactor, reactor_registration())
      assert :counters.get(calls, 1) == 0
    end

    test "leaves the observer to its own call when multiplexing is turned off" do
      test = self()

      %{channel: channel} =
        start_channel(
          enabled: false,
          capabilities_fun: fn _ ->
            send(test, :asked)
            {:ok, [@capability]}
          end
        )

      assert :unsupported = Channel.open(channel, :grpc, :reactor, reactor_registration())
      refute_receive :asked, 50
    end

    test "leaves the observer to its own call when the kernel cannot be asked, and asks again" do
      answers = :counters.new(1, [])

      %{channel: channel} =
        start_channel(
          capabilities_fun: fn _ ->
            :counters.add(answers, 1, 1)

            if :counters.get(answers, 1) == 1,
              do: {:error, :unavailable},
              else: {:ok, [@capability]}
          end
        )

      assert :unsupported = Channel.open(channel, :grpc, :reactor, reactor_registration())
      assert {:ok, _stream} = Channel.open(channel, :grpc, :reactor, reactor_registration())
    end

    test "asks the kernel once for a connection" do
      asked = :counters.new(1, [])

      %{channel: channel} =
        start_channel(
          capabilities_fun: fn _ ->
            :counters.add(asked, 1, 1)
            {:ok, [@capability]}
          end
        )

      open!(channel)
      open!(channel)

      assert :counters.get(asked, 1) == 1
    end
  end

  describe "registering" do
    test "sends registrations that are ready together in one write" do
      %{channel: channel} = start_channel(flush_interval: 50)

      first = open!(channel, :reactor, reactor_registration("first"))
      second = open!(channel, :reducer, reducer_registration())

      assert_receive {:wrote, _call, %Wire.MultiplexedClientMessage{Messages: [one, two]}}, 500

      assert %Wire.MultiplexedStreamMessage{StreamId: first_id, Kind: :Reactor} = one
      assert one."Reactor"."Content"."Value0"."ConnectionId" == "first"
      assert first_id == first.id
      assert %Wire.MultiplexedStreamMessage{StreamId: second_id, Kind: :Reducer} = two
      assert two."Reducer"."Content"."Value0"."ConnectionId" == "reducer"
      assert second_id == second.id
      refute_receive {:wrote, _, _}, 100
    end

    test "splits a write that would exceed the largest batch" do
      %{channel: channel} = start_channel(flush_interval: 50, max_batch: 2)

      for index <- 1..5, do: open!(channel, :reactor, reactor_registration("r#{index}"))

      assert_receive {:wrote, _, %{Messages: [_, _]}}, 500
      assert_receive {:wrote, _, %{Messages: [_, _]}}, 500
      assert_receive {:wrote, _, %{Messages: [_]}}, 500
    end

    test "names the kind only on the first message of a stream" do
      %{channel: channel} = start_channel()
      stream = open!(channel)
      assert_receive {:wrote, _, _}, 500

      assert :ok = ObserverStream.send_request(stream, reactor_result(7))

      assert_receive {:wrote, _, %{Messages: [message]}}, 500
      assert message."Kind" == :Unspecified
      assert message."StreamId" == stream.id
      assert message."Reactor"."Content"."Value1"."DeliveryId" == 7
    end

    test "keeps the order of one stream's messages" do
      %{channel: channel} = start_channel(flush_interval: 50)
      stream = open!(channel)

      for delivery_id <- 1..3,
          do: ObserverStream.send_request(stream, reactor_result(delivery_id))

      assert_receive {:wrote, _, %{Messages: messages}}, 500

      assert [nil, 1, 2, 3] =
               Enum.map(messages, fn message ->
                 case message."Reactor"."Content" do
                   %{Value1: %{DeliveryId: id}} -> id
                   _ -> nil
                 end
               end)
    end
  end

  describe "delivering" do
    test "gives each stream only its own messages, in order" do
      %{channel: channel} = start_channel()
      first = open!(channel)
      second = open!(channel)
      reader = reader!()

      feed(reader, delivery(first.id, 1, "a1"))
      feed(reader, delivery(second.id, 1, "b1"))
      feed(reader, delivery(first.id, 2, "a2"))

      assert {:message, %Reactors.EventsToObserve{Partition: "a1"}} = Channel.next(first)
      assert {:message, %Reactors.EventsToObserve{Partition: "a2"}} = Channel.next(first)
      assert {:message, %Reactors.EventsToObserve{Partition: "b1"}} = Channel.next(second)
    end

    test "gives a reducer stream its reduce operations" do
      %{channel: channel} = start_channel()
      stream = open!(channel, :reducer, reducer_registration())
      reader = reader!()

      feed(reader, %Wire.MultiplexedServerMessage{
        StreamId: stream.id,
        Sequence: 1,
        Reducer: %Wire.ReduceOperationMessage{Partition: "p"}
      })

      assert {:message, %Reducers.ReduceOperationMessage{Partition: "p"}} = Channel.next(stream)
    end

    test "wakes a handler that is already waiting" do
      %{channel: channel} = start_channel()
      stream = open!(channel)
      reader = reader!()

      waiting = Task.async(fn -> Channel.next(stream) end)
      Process.sleep(30)
      feed(reader, delivery(stream.id, 1, "late"))

      assert {:message, %{Partition: "late"}} = Task.await(waiting)
    end

    test "a slow handler does not hold back another" do
      %{channel: channel} = start_channel()
      slow = open!(channel)
      fast = open!(channel)
      reader = reader!()

      for sequence <- 1..50 do
        feed(reader, delivery(slow.id, sequence, "slow"))
        feed(reader, delivery(fast.id, sequence, "fast-#{sequence}"))
      end

      for sequence <- 1..50 do
        expected = "fast-#{sequence}"
        assert {:message, %{Partition: ^expected}} = Channel.next(fast)
      end
    end

    test "the recv enumerable yields deliveries and ends when the kernel completes the stream" do
      %{channel: channel} = start_channel()
      stream = open!(channel)
      reader = reader!()
      feed(reader, delivery(stream.id, 1, "a"))

      feed(reader, %Wire.MultiplexedServerMessage{
        StreamId: stream.id,
        Sequence: 2,
        End: %Wire.MultiplexedStreamEnd{StatusCode: 0}
      })

      assert {:ok, enumerable} = ObserverStream.recv(stream)
      assert [{:ok, %{Partition: "a"}}] = Enum.to_list(enumerable)
    end
  end

  describe "a stream the kernel ends" do
    test "with a failure status raises the error a failed call would have" do
      %{channel: channel} = start_channel()
      failing = open!(channel)
      other = open!(channel)
      reader = reader!()

      feed(reader, %Wire.MultiplexedServerMessage{
        StreamId: failing.id,
        Sequence: 1,
        End: %Wire.MultiplexedStreamEnd{StatusCode: 14, Detail: "kernel is stopping"}
      })

      feed(reader, delivery(other.id, 1, "still here"))

      assert {:error, %GRPC.RPCError{status: 14, message: "kernel is stopping"}} =
               Channel.next(failing)

      assert {:message, %{Partition: "still here"}} = Channel.next(other)
    end

    test "with status zero completes it" do
      %{channel: channel} = start_channel()
      stream = open!(channel)
      reader = reader!()

      feed(reader, %Wire.MultiplexedServerMessage{
        StreamId: stream.id,
        Sequence: 1,
        End: %Wire.MultiplexedStreamEnd{StatusCode: 0}
      })

      assert :done = Channel.next(stream)
    end
  end

  describe "a gap in the sequence of a stream" do
    test "fails the whole call" do
      %{channel: channel} = start_channel()
      first = open!(channel)
      second = open!(channel)
      reader = reader!()

      feed(reader, delivery(first.id, 1, "a"))
      feed(reader, delivery(first.id, 3, "skipped"))

      assert {:message, %{Partition: "a"}} = Channel.next(first)
      assert {:error, %GRPC.RPCError{message: message}} = Channel.next(first)
      assert message =~ "expected message 2 but got 3"
      assert {:error, %GRPC.RPCError{}} = Channel.next(second)
    end
  end

  describe "closing" do
    test "tells the kernel to stop observing for the stream" do
      %{channel: channel} = start_channel()
      first = open!(channel)
      _second = open!(channel)
      assert_receive {:wrote, _, _}, 500

      Channel.close(first)

      assert_receive {:wrote, _, %{Messages: [message]}}, 500
      assert message."StreamId" == first.id
      assert message."Close"
      refute_receive {:ended, _}, 50
    end

    test "ends the call with the last stream and opens a new one for the next" do
      %{channel: channel, calls: calls} = start_channel()
      stream = open!(channel)
      assert_receive {:wrote, _, _}, 500

      Channel.close(stream)

      assert_receive {:wrote, _, %{Messages: [%{Close: true}]}}, 500
      assert_receive {:ended, {:call, 1}}, 500

      open!(channel)
      assert :counters.get(calls, 1) == 2
    end

    test "wakes a handler that is waiting on the stream" do
      %{channel: channel} = start_channel()
      stream = open!(channel)
      waiting = Task.async(fn -> Channel.next(stream) end)
      Process.sleep(30)

      Channel.close(stream)

      assert :done = Task.await(waiting)
    end

    test "closes the stream of a handler that died" do
      %{channel: channel} = start_channel()
      owner = spawn(fn -> receive do: (:stop -> :ok) end)
      parent = self()

      opener =
        spawn(fn ->
          send(parent, {:opened, Channel.open(channel, :grpc, :reactor, reactor_registration())})
          receive do: (:stop -> :ok)
        end)

      assert_receive {:opened, {:ok, _stream}}, 500
      assert_receive {:wrote, _, _}, 500
      send(opener, :stop)
      send(owner, :stop)

      assert_receive {:wrote, _, %{Messages: [%{Close: true}]}}, 500
      assert_receive {:ended, _}, 500
    end
  end

  describe "the shared call failing" do
    test "fails every open stream and opens a new call for the next" do
      %{channel: channel, calls: calls} = start_channel()
      first = open!(channel)
      second = open!(channel)
      reader = reader!()

      send(reader, {:kernel_fails, %GRPC.RPCError{status: 14, message: "gone"}})

      assert {:error, %GRPC.RPCError{status: 14}} = Channel.next(first)
      assert {:error, %GRPC.RPCError{status: 14}} = Channel.next(second)
      assert_receive {:ended, {:call, 1}}, 500

      Channel.close(first)
      Channel.close(second)
      refute_receive {:wrote, _, %{Messages: [%{Close: true}]}}, 50

      reopened = open!(channel)
      assert :counters.get(calls, 1) == 2
      assert reopened.id > second.id
    end

    test "ending completes every open stream" do
      %{channel: channel} = start_channel()
      stream = open!(channel)
      reader = reader!()

      send(reader, :kernel_ends)

      assert :done = Channel.next(stream)
    end

    test "a failed write fails the call" do
      %{channel: channel} =
        start_channel(send_fun: fn _call, _message -> raise "the connection is closed" end)

      stream = open!(channel)

      assert {:error, %RuntimeError{message: "the connection is closed"}} = Channel.next(stream)
    end

    test "a call that cannot be opened is an error for the observer, not a fallback" do
      %{channel: channel} = start_channel(open_fun: fn _ -> {:error, :closed} end)

      assert {:error, :closed} = Channel.open(channel, :grpc, :reactor, reactor_registration())
    end
  end
end
