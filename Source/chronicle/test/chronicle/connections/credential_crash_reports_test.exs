# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Connections.CredentialCrashReportsTest do
  use ExUnit.Case, async: false

  alias Chronicle.Connections.{CredentialRegistry, ResponseCrashRedaction}
  alias GRPC.Client.Adapters.Mint.ConnectionProcess

  @api_key "api-key-secret-for-crash-reports"
  @bearer "bearer-token-secret-for-crash-reports"

  # Receives every log event after the primary filters, the way any handler does.
  def log(event, %{test: test}), do: send(test, {:logged, event})

  setup do
    :ok = ResponseCrashRedaction.install!()
    :ok = CredentialRegistry.remember(@api_key)
    :ok = CredentialRegistry.remember(@bearer)
    id = :"credential_crash_#{System.unique_integer([:positive])}"
    :ok = :logger.add_handler(id, __MODULE__, %{test: self(), level: :all})
    Process.flag(:trap_exit, true)
    filters = :logger.get_primary_config().filters
    :ok = :logger.set_primary_config(:filters, with_sasl_reports(filters))

    on_exit(fn ->
      :logger.set_primary_config(:filters, filters)
      :logger.remove_handler(id)
      CredentialRegistry.forget(@api_key)
      CredentialRegistry.forget(@bearer)
    end)

    {:ok, server: start_h2_server()}
  end

  test "a crashed Mint ConnectionProcess never prints the HPACK-held API key or bearer token",
       %{server: server} do
    pid = open_connection_process(server)
    crash(pid, fn -> catch_exit(GenServer.call(pid, :unsupported_request)) end)

    text = collect()
    assert text =~ "ConnectionProcess"
    refute text =~ @api_key
    refute text =~ @bearer
  end

  test "a crashed GRPC.Client.Connection never prints its channel headers", %{server: server} do
    {:ok, channel} =
      GRPC.Client.Connection.connect("ipv4:127.0.0.1:#{server.port}",
        adapter: GRPC.Client.Adapters.Mint,
        headers: [{"api-key", @api_key}, {"authorization", "Bearer #{@bearer}"}],
        connect_timeout: 5_000
      )

    pid =
      GenServer.whereis(
        {:via, Registry, {GRPC.Client.Registry, {GRPC.Client.Connection, channel.ref}}}
      )

    crash(pid, fn -> GenServer.cast(pid, :unsupported_cast) end)
    on_exit(fn -> GRPC.Client.Connection.disconnect(channel) end)

    text = collect()
    assert text =~ "GRPC.Client.Connection"
    refute text =~ @api_key
    refute text =~ @bearer
  end

  test "supervisor child_terminated reports keep the credentials out", %{server: server} do
    {:ok, supervisor} =
      Supervisor.start_link(
        [
          %{
            id: :grpc_mint_connection,
            restart: :transient,
            start: {__MODULE__.Child, :start_link, [server.port]}
          }
        ],
        strategy: :one_for_one,
        max_restarts: 0
      )

    [{_, child, _, _}] = Supervisor.which_children(supervisor)
    crash(child, fn -> GenServer.cast(child, :unsupported_cast) end)

    text = collect()
    assert text =~ "terminated"
    refute text =~ @api_key
    refute text =~ @bearer
  end

  test "supervisor start_error reports keep the credentials out" do
    stream = %GRPC.Client.Stream{
      channel: %GRPC.Channel{headers: [{"api-key", @api_key}]},
      headers: %{"authorization" => "Bearer #{@bearer}"}
    }

    Process.flag(:trap_exit, true)

    {:error, _} =
      Supervisor.start_link(
        [
          %{
            id: :failing,
            start: {__MODULE__.Failing, :start_link, [stream]}
          }
        ],
        strategy: :one_for_one
      )

    text = collect()
    refute text =~ @api_key
    refute text =~ @bearer
  end

  test "plain string and format log events lose registered secrets" do
    require Logger
    Logger.error("linked process exited: #{inspect({:state, @api_key, "Bearer #{@bearer}"})}")
    :logger.error("format ~p", [%{"api-key" => @api_key, other: @bearer}])

    text = collect()
    assert text =~ "linked process exited"
    refute text =~ @api_key
    refute text =~ @bearer
  end

  test "unrelated events pass through the filter unchanged" do
    event = %{level: :error, meta: %{}, msg: {:string, "nothing secret here"}}
    assert ResponseCrashRedaction.filter(event, nil) == event
    event = %{level: :info, meta: %{}, msg: {:report, %{label: {:app, :thing}, value: 1}}}
    assert ResponseCrashRedaction.filter(event, nil) == event
  end

  defmodule Child do
    @moduledoc false
    def start_link(port) do
      ConnectionProcess.start_link(:http, "127.0.0.1", port, protocols: [:http2])
      |> case do
        {:ok, pid} ->
          Chronicle.Connections.CredentialCrashReportsTest.send_request(pid)
          {:ok, pid}

        other ->
          other
      end
    end
  end

  defmodule Failing do
    @moduledoc false
    def start_link(stream), do: {:error, {:cannot_start, stream}}
  end

  def send_request(pid) do
    :ok =
      ConnectionProcess.request(
        pid,
        "POST",
        "/svc/Method",
        [
          {"api-key", @api_key},
          {"authorization", "Bearer #{@bearer}"},
          {"content-type", "application/grpc"}
        ],
        :stream,
        stream_response_pid: self()
      )
      |> elem(0)
      |> then(fn _ -> :ok end)
  end

  defp open_connection_process(server) do
    {:ok, pid} =
      ConnectionProcess.start_link(:http, "127.0.0.1", server.port, protocols: [:http2])

    send_request(pid)
    pid
  end

  defp crash(pid, trigger) do
    ref = Process.monitor(pid)
    trigger.()
    assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 5_000
    Process.sleep(100)
  end

  # Production applications that set `handle_sasl_reports: true` get proc_lib crash and
  # supervisor reports; enable them so those shapes are exercised through the real pipeline
  # (the client filter runs first, Elixir's translator formats what is left).
  defp with_sasl_reports(filters) do
    Enum.map(filters, fn
      {:logger_translator, {fun, config}} -> {:logger_translator, {fun, %{config | sasl: true}}}
      other -> other
    end)
  end

  defp collect(acc \\ []) do
    receive do
      {:logged, event} -> collect([render(event) | acc])
    after
      200 -> acc |> Enum.reverse() |> Enum.join("\n")
    end
  end

  defp render(event) do
    formatted =
      :logger_formatter.format(event, %{
        template: [:msg],
        single_line: false,
        depth: :unlimited,
        chars_limit: :unlimited
      })

    IO.iodata_to_binary([
      formatted,
      inspect(event.msg, limit: :infinity, printable_limit: :infinity)
    ])
  end

  defp start_h2_server do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, {_, port}} = :inet.sockname(listener)

    acceptor =
      spawn_link(fn ->
        accept_loop(listener)
      end)

    on_exit(fn ->
      Process.unlink(acceptor)
      Process.exit(acceptor, :kill)
      :gen_tcp.close(listener)
    end)

    %{port: port}
  end

  defp accept_loop(listener) do
    case :gen_tcp.accept(listener) do
      {:ok, socket} ->
        :ok = :gen_tcp.send(socket, <<0::24, 4, 0, 0::32>>)
        spawn(fn -> drain(socket) end)
        accept_loop(listener)

      {:error, _} ->
        :ok
    end
  end

  defp drain(socket) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, _} -> drain(socket)
      {:error, _} -> :ok
    end
  end
end
