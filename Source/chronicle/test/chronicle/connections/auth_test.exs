# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Connections.AuthTest do
  use ExUnit.Case, async: true

  alias Chronicle.Connections.Auth

  test "a failed token response closes the open Mint socket" do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, {_, port}} = :inet.sockname(listener)

    {:ok, result_agent} = Agent.start_link(fn -> nil end)

    spawn(fn ->
      {:ok, socket} = :gen_tcp.accept(listener, 5_000)
      result = await_closed(socket)
      :gen_tcp.close(socket)
      :gen_tcp.close(listener)
      Agent.update(result_agent, fn _ -> result end)
    end)

    request_fun = fn conn, method, path, headers, body ->
      result = Mint.HTTP.request(conn, method, path, headers, body)
      # Mint marks the connection closed on a transport error but leaves the
      # socket open. Keep the server open to verify Auth closes the socket.
      send(self(), {:tcp_error, conn.socket, :closed})
      result
    end

    assert {:error, {:stream_error, _reason}} =
             Auth.fetch_token_with_expiry(
               "127.0.0.1",
               port,
               "id",
               "secret",
               true,
               true,
               [],
               request_fun
             )

    assert_closed(result_agent, System.monotonic_time(:millisecond) + 6_000)
  end

  test "a failed token request closes the connected socket" do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, {_, port}} = :inet.sockname(listener)
    {:ok, result_agent} = Agent.start_link(fn -> nil end)

    spawn(fn ->
      {:ok, socket} = :gen_tcp.accept(listener, 5_000)
      result = await_closed(socket)
      :gen_tcp.close(socket)
      :gen_tcp.close(listener)
      Agent.update(result_agent, fn _ -> result end)
    end)

    request_fun = fn conn, _method, _path, _headers, _body ->
      {:error, conn, :request_failed}
    end

    assert {:error, {:request_error, :request_failed}} =
             Auth.fetch_token_with_expiry(
               "127.0.0.1",
               port,
               "id",
               "secret",
               true,
               true,
               [],
               request_fun
             )

    assert_closed(result_agent, System.monotonic_time(:millisecond) + 6_000)
  end

  defp assert_closed(agent, deadline) do
    case Agent.get(agent, & &1) do
      :closed ->
        :ok

      nil ->
        assert System.monotonic_time(:millisecond) < deadline, "server did not finish"
        Process.sleep(10)
        assert_closed(agent, deadline)

      result ->
        flunk("OAuth socket stayed open: #{inspect(result)}")
    end
  end

  defp await_closed(socket) do
    case :gen_tcp.recv(socket, 0, 5_000) do
      {:ok, _data} -> await_closed(socket)
      {:error, :closed} -> :closed
      other -> other
    end
  end
end
