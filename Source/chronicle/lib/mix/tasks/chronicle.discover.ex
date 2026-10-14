# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Mix.Tasks.Chronicle.Discover do
  @shortdoc "Prints the Chronicle discovery report, optionally checking it for identity drift"

  @moduledoc """
  Prints the artifacts `Chronicle.Artifacts.discover/1` finds in an OTP application, and
  optionally compares them with a running kernel for artifact identity drift (see
  `Chronicle.Discovery.DriftDetector`).

  ## Usage

      mix chronicle.discover --otp-app my_app
      mix chronicle.discover --otp-app my_app \\
        --connection-string "chronicle://localhost:35000" --fail-on-drift

  ## Options

    * `--otp-app` — **(required)** the OTP application to discover Chronicle artifacts from.
    * `--connection-string` — a Chronicle connection string. When given, the task also
      fetches the kernel's current event types and observers (event store `"default"`,
      namespace `"Default"` — the same defaults `Chronicle.Client` uses) and reports any
      artifact identity drift.
    * `--fail-on-drift` — exit `1` when a `:warning`-severity drift finding exists. Has no
      effect without `--connection-string`.

  ## Exit codes

    * `0` — printed cleanly; no drift found, or none was requested.
    * `1` — drift was requested and a `:warning`-severity finding exists, with `--fail-on-drift`.
    * `2` — could not run: `--otp-app` missing, or the kernel couldn't be reached.
  """

  use Mix.Task

  alias Chronicle.Connections.Connection
  alias Chronicle.Discovery.{DriftDetector, Report}

  @event_store "default"
  @namespace "Default"

  @impl Mix.Task
  def run(args) do
    {output, code} = execute(args)
    Mix.shell().info(output)
    if code != 0, do: System.halt(code)
  end

  @doc false
  @spec execute([String.t()]) :: {String.t(), 0 | 1 | 2}
  def execute(args) do
    {opts, _rest, invalid} =
      OptionParser.parse(args,
        strict: [otp_app: :string, connection_string: :string, fail_on_drift: :boolean]
      )

    cond do
      invalid != [] ->
        {"Unrecognized option(s): #{inspect(invalid)}", 2}

      is_nil(Keyword.get(opts, :otp_app)) ->
        {"--otp-app is required", 2}

      true ->
        run_discovery(opts)
    end
  end

  defp run_discovery(opts) do
    otp_app = opts |> Keyword.fetch!(:otp_app) |> String.to_atom()
    Application.ensure_loaded(otp_app)
    report = Chronicle.Artifacts.report(otp_app)

    case Keyword.get(opts, :connection_string) do
      nil ->
        {Report.format(report), 0}

      connection_string ->
        check_drift(report, connection_string, Keyword.get(opts, :fail_on_drift, false))
    end
  end

  defp check_drift(report, connection_string, fail_on_drift?) do
    case dial(connection_string) do
      {:ok, channel, connection} ->
        result =
          DriftDetector.detect(channel, report, event_store: @event_store, namespace: @namespace)

        GenServer.stop(connection)
        format_result(report, result, fail_on_drift?)

      {:error, reason} ->
        {"#{Report.format(report)}\n\nCould not connect: #{inspect(reason)}", 2}
    end
  end

  defp dial(connection_string) do
    with {:ok, connection} <- Connection.start_link(connection_string: connection_string),
         :ok <- Connection.connect(connection, 5_000),
         {:ok, channel} <- Connection.channel(connection) do
      {:ok, channel, connection}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp format_result(report, {:ok, findings}, fail_on_drift?) do
    output = Report.format(report) <> "\n\n" <> format_findings(findings)
    blocking? = fail_on_drift? and Enum.any?(findings, &(&1.severity == :warning))
    {output, if(blocking?, do: 1, else: 0)}
  end

  defp format_result(report, {:error, reason}, _fail_on_drift?) do
    {"#{Report.format(report)}\n\nCould not check for drift: #{inspect(reason)}", 2}
  end

  defp format_findings([]), do: "No artifact identity drift found."

  defp format_findings(findings) do
    lines =
      Enum.map(findings, fn finding ->
        "  [#{finding.severity}] #{finding.kind} #{finding.id}: #{finding.reason}"
      end)

    Enum.join(["Artifact identity drift found:" | lines], "\n")
  end
end
