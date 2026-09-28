# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Connections.ServerPushTest do
  use ExUnit.Case, async: false

  alias Chronicle.Connections.Connection

  test "the real Mint adapter sends enable_push: false through every per-call option path" do
    for adapter_opts <- [
          [],
          [client_settings: [enable_push: true, initial_window_size: 4_000_000]],
          [config_options: [client_settings: [initial_window_size: 4_000_000]]],
          [config_options: [client_settings: [enable_push: true]]],
          [config_options: [retry: 0]]
        ] do
      {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
      {:ok, {_, port}} = :inet.sockname(listener)
      parent = self()

      {:ok, connection} =
        Connection.start_link(
          connection_string: "chronicle://localhost:#{port}?disableTls=true",
          grpc_options: [adapter_opts: adapter_opts],
          connect_fun: fn _, opts ->
            send(parent, {:options, opts})
            {:ok, %{}}
          end
        )

      assert :ok = Connection.connect(connection, 2_000)
      assert_receive {:options, options}

      assert options[:adapter_opts][:client_settings][:enable_push] == false
      assert options[:adapter_opts][:config_options][:client_settings][:enable_push] == false

      task =
        Task.async(fn ->
          GRPC.Client.Adapters.Mint.connect(
            %GRPC.Channel{host: "localhost", port: port, scheme: "http"},
            options[:adapter_opts]
          )
        end)

      {:ok, socket} = :gen_tcp.accept(listener, 5_000)
      assert {:ok, "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"} = :gen_tcp.recv(socket, 24, 5_000)
      assert {:ok, <<length::24, 4, _flags, 0::32>>} = :gen_tcp.recv(socket, 9, 5_000)
      assert {:ok, payload} = :gen_tcp.recv(socket, length, 5_000)

      assert <<2::16, 0::32>> in for(<<setting::16, value::32 <- payload>>,
               do: <<setting::16, value::32>>
             )

      :ok = :gen_tcp.send(socket, <<0::24, 4, 0, 0::32>>)

      case Task.await(task, 5_000) do
        {:ok, channel} -> GRPC.Client.Adapters.Mint.disconnect(channel)
        {:error, reason} -> flunk("Mint connect failed: #{inspect(reason)}")
      end

      Connection.disconnect(connection)
      :gen_tcp.close(socket)
      :gen_tcp.close(listener)
    end
  end

  test "application Mint options cannot override the push restriction" do
    previous = Application.get_env(:grpc, GRPC.Client.Adapters.Mint)

    on_exit(fn ->
      if previous == nil,
        do: Application.delete_env(:grpc, GRPC.Client.Adapters.Mint),
        else: Application.put_env(:grpc, GRPC.Client.Adapters.Mint, previous)
    end)

    Process.flag(:trap_exit, true)

    for settings <- [[initial_window_size: 4_000_000], [enable_push: true]] do
      Application.put_env(:grpc, GRPC.Client.Adapters.Mint, client_settings: settings)

      assert {:error, {%ArgumentError{message: message}, _}} =
               Connection.start_link(
                 connection_string: "chronicle://localhost?disableTls=true",
                 grpc_options: [
                   adapter_opts: [config_options: [client_settings: [enable_push: false]]]
                 ],
                 auto_connect: false
               )

      assert message =~ "enable_push: false"
    end

    Application.put_env(:grpc, GRPC.Client.Adapters.Mint,
      client_settings: [initial_window_size: 4_000_000, enable_push: false]
    )

    assert {:ok, connection} = Connection.start_link(auto_connect: false)
    Connection.disconnect(connection)
  end
end
