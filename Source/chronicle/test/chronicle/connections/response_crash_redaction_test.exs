# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Connections.ResponseCrashRedactionTest do
  use ExUnit.Case, async: false

  alias Chronicle.Connections.{
    AuthInterceptor,
    Connection,
    ConnectionString,
    ResponseCrashRedaction,
    TokenProvider
  }

  alias GRPC.Client.Adapters.Mint.StreamResponseProcess

  test "malformed trailers never disclose an API key in the response process crash log" do
    secret = "api-secret-for-response-crash"
    parent = self()

    {:ok, connection} =
      Connection.start_link(
        connection_string: "chronicle://localhost:35000?apiKey=#{secret}&disableTls=true",
        connect_fun: fn _target, opts ->
          send(parent, {:options, opts})
          {:ok, %GRPC.Channel{adapter: opts[:adapter], headers: opts[:headers]}}
        end,
        auto_connect: true
      )

    assert :ok = Connection.connect(connection, 1_000)
    assert_receive {:options, opts}
    assert opts[:headers] == [{"api-key", secret}]
    assert {:ok, channel} = Connection.channel(connection)

    log = crash_response_stream(%GRPC.Client.Stream{channel: channel})
    assert log =~ "gRPC Mint response process terminated"
    refute log =~ secret
  end

  test "malformed trailers never disclose a fetched OAuth token in the response process crash log" do
    :ok = ResponseCrashRedaction.install!()
    secret = "oauth-secret-for-response-crash"

    {:ok, provider} =
      TokenProvider.start_link(
        connection_string: ConnectionString.parse("chronicle://user:pass@localhost:35000"),
        fetch_fun: fn _connection_string -> {:ok, {secret, 3_600}} end
      )

    stream = %GRPC.Client.Stream{channel: %GRPC.Channel{adapter: GRPC.Client.Adapters.Mint}}

    authenticated =
      AuthInterceptor.call(
        stream,
        :request,
        fn stream, _request -> stream end,
        AuthInterceptor.init(provider: provider)
      )

    assert authenticated.headers["authorization"] == "Bearer #{secret}"
    log = crash_response_stream(authenticated)
    assert log =~ "gRPC Mint response process terminated"
    refute log =~ secret
  end

  describe "filter/2 on other crash report fields" do
    @secret "header-secret"

    defp report_event(fields) do
      %{
        level: :error,
        meta: %{},
        msg: {:report, Map.merge(%{label: {:gen_server, :terminate}, state: %{}}, fields)}
      }
    end

    defp stream_with_secret do
      %GRPC.Client.Stream{
        channel: %GRPC.Channel{headers: [{"api-key", @secret}]},
        headers: %{"authorization" => "Bearer #{@secret}"}
      }
    end

    test "redacts a last_message and a reason that carry a stream" do
      event =
        report_event(%{
          last_message: {:request, stream_with_secret()},
          reason: {%RuntimeError{message: "x"}, [{Mod, :fun, [stream_with_secret()], []}]}
        })

      %{msg: {:report, report}} = ResponseCrashRedaction.filter(event, nil)

      refute inspect(report) =~ @secret
      assert report.label == {:gen_server, :terminate}
    end

    test "redacts when only a channel with headers is present" do
      event = report_event(%{last_message: [%GRPC.Channel{headers: [{"api-key", @secret}]}]})

      %{msg: {:report, report}} = ResponseCrashRedaction.filter(event, nil)
      refute inspect(report) =~ @secret
    end

    test "leaves unrelated reports untouched" do
      event = report_event(%{last_message: :ping, reason: :normal})
      assert ResponseCrashRedaction.filter(event, nil) == event
    end
  end

  test "install!/0 is idempotent" do
    assert :ok = ResponseCrashRedaction.install!()
    assert :ok = ResponseCrashRedaction.install!()
  end

  defp crash_response_stream(stream) do
    Process.flag(:trap_exit, true)

    ExUnit.CaptureLog.capture_log(fn ->
      {:ok, pid} = StreamResponseProcess.start_link(stream, false)
      monitor = Process.monitor(pid)

      assert {:error, _reason} =
               StreamResponseProcess.consume(pid, :trailers, [{"grpc-status", "invalid"}])

      assert_receive {:DOWN, ^monitor, :process, ^pid, _reason}, 2_000
      Logger.flush()
    end)
  end
end
