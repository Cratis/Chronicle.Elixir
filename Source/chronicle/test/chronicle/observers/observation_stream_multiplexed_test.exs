# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Observers.ObservationStreamMultiplexedTest do
  use ExUnit.Case, async: true

  alias Chronicle.Observers.Multiplexed.{Channel, ObserverStream}
  alias Chronicle.Observers.ObservationStream
  alias Cratis.Chronicle.Contracts.Observation.Reactors.ReactorMessage

  defp start_channel(name, capabilities) do
    test = self()

    start_supervised!({
      Channel,
      # The kernel stays silent: the call is open and nothing arrives.
      name: name,
      flush_interval: 1,
      capabilities_fun: fn _ -> {:ok, capabilities} end,
      open_fun: fn _ -> {:ok, :call, []} end,
      send_fun: fn _call, message -> send(test, {:wrote, message}) end,
      recv_fun: fn _ -> {:ok, silence()} end,
      end_fun: fn _ -> :ok end
    })
  end

  defp silence do
    Stream.repeatedly(fn ->
      receive do
        :never -> :never
      end
    end)
  end

  defp own_call(test) do
    fn _channel ->
      send(test, :opened_own_call)
      %GRPC.Client.Stream{payload: %{response: {:error, :own_call}}}
    end
  end

  test "opens a share of the multiplexed call when the kernel supports it" do
    name = :"#{__MODULE__}.supported"
    start_channel(name, ["multiplexed-observation"])

    assert {:ok, %ObserverStream{kind: :reducer}, []} =
             ObservationStream.open(:grpc, own_call(self()), %ReactorMessage{}, name, :reducer)

    assert_receive {:wrote, %{Messages: [%{Kind: :Reducer}]}}, 500
    refute_receive :opened_own_call, 50
  end

  test "opens the observer's own call when the kernel does not support it" do
    name = :"#{__MODULE__}.unsupported"
    start_channel(name, [])

    assert {:error, :own_call} =
             ObservationStream.open(:grpc, own_call(self()), %ReactorMessage{}, name, :reactor)

    assert_receive :opened_own_call
  end

  test "opens the observer's own call when the client runs no multiplexed channel" do
    assert {:error, :own_call} =
             ObservationStream.open(
               :grpc,
               own_call(self()),
               %ReactorMessage{},
               :"#{__MODULE__}.not_running",
               :reactor
             )

    assert {:error, :own_call} =
             ObservationStream.open(:grpc, own_call(self()), %ReactorMessage{}, nil, :reactor)
  end

  test "closes a multiplexed stream without stopping response processes it does not own" do
    name = :"#{__MODULE__}.close"
    start_channel(name, ["multiplexed-observation"])

    {:ok, stream, []} =
      ObservationStream.open(:grpc, own_call(self()), %ReactorMessage{}, name, :reactor)

    assert_receive {:wrote, _}, 500

    assert :ok = ObservationStream.close(stream, [])

    assert_receive {:wrote, %{Messages: [%{Close: true}]}}, 500
  end
end
