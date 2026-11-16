# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Observers.ObservationStreamTest do
  use ExUnit.Case, async: false

  alias Chronicle.Connections.Connection
  alias Chronicle.Observers.ObservationStream
  alias Cratis.Chronicle.Contracts.Observation.Reactors.ReactorMessage
  alias Cratis.Chronicle.Contracts.Observation.Reactors.Reactors
  alias GRPC.Client.Adapters.Mint.StreamResponseProcess

  # A Mint connection to a socket that accepts but never answers: the stream opens and the
  # registration is sent, and nothing reads the stream to the end.
  setup do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, {_, port}} = :inet.sockname(listener)
    on_exit(fn -> :gen_tcp.close(listener) end)

    {:ok, connection} =
      Connection.start_link(connection_string: "chronicle://localhost:#{port}?disableTls=true")

    {:ok, socket} = :gen_tcp.accept(listener, 5_000)
    on_exit(fn -> :gen_tcp.close(socket) end)
    assert :ok = Connection.connect(connection, 5_000)
    {:ok, channel} = Connection.channel(connection)
    %{channel: channel}
  end

  describe "opening on a working connection" do
    test "returns the stream and the response process it started", %{channel: channel} do
      assert {:ok, %GRPC.Client.Stream{}, [response_process]} =
               ObservationStream.open(channel, &Reactors.Stub.observe/1, %ReactorMessage{})

      assert Process.alive?(response_process)
      assert response_process in links()
    end
  end

  describe "closing a stream nobody reads to the end" do
    test "stops its response process", %{channel: channel} do
      {:ok, stream, [response_process]} =
        ObservationStream.open(channel, &Reactors.Stub.observe/1, %ReactorMessage{})

      monitor = Process.monitor(response_process)
      assert :ok = ObservationStream.close(stream, [response_process])

      assert_receive {:DOWN, ^monitor, :process, ^response_process, _}, 1_000
      refute response_process in links()
    end
  end

  describe "opening on a connection that has gone away" do
    test "returns an error and leaves no response process behind", %{channel: channel} do
      {:ok, _} = GRPC.Stub.disconnect(channel)

      assert {:error, _reason} =
               ObservationStream.open(channel, &Reactors.Stub.observe/1, %ReactorMessage{})

      assert response_processes() == []
    end
  end

  describe "opening a stream the adapter could not start" do
    test "returns the adapter's error instead of sending on it" do
      observe = fn _channel ->
        stream = %GRPC.Client.Stream{payload: %{}}
        {:ok, response_process} = StreamResponseProcess.start_link(stream, false)

        %{
          stream
          | payload: %{
              response: {:error, "the connection is closed"},
              stream_response_pid: response_process
            }
        }
      end

      assert {:error, "the connection is closed"} =
               ObservationStream.open(%GRPC.Channel{}, observe, %ReactorMessage{})

      assert response_processes() == []
    end
  end

  defp links do
    {:links, links} = Process.info(self(), :links)
    links
  end

  # A stopped process may still be listed for the instant before its exit signal lands.
  defp response_processes do
    Process.sleep(50)

    Enum.filter(links(), fn pid ->
      is_pid(pid) and
        match?(
          {:dictionary, dictionary} when is_list(dictionary),
          Process.info(pid, :dictionary)
        ) and
        match?(
          {StreamResponseProcess, _, _},
          Keyword.get(elem(Process.info(pid, :dictionary), 1), :"$initial_call")
        )
    end)
  end
end
