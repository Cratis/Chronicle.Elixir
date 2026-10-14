# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Captures do
  @moduledoc """
  Idiomatic API for working with Chronicle captures.

  Captures turn data that arrives from outside the event log into events appended to this
  event store. Declare one with `use Chronicle.Captures.Capture` (see its moduledoc for the
  DSL) and either register it with `Chronicle.Client`'s `captures:` option (or `otp_app:`
  auto-discovery), or call the functions here directly.

  ## Usage

      {:ok, _} = Chronicle.Captures.register(MyApp.Captures.InvoiceCapture)
      {:ok, _} = Chronicle.Captures.start(MyApp.Captures.InvoiceCapture)
      {:ok, captures} = Chronicle.Captures.list()

  ## Options

  Every function accepts:

    * `:client` — the client name (default: `Chronicle.Client`)
  """

  alias Bcl.Guid, as: BclGuid
  alias Chronicle.Artifacts
  alias Chronicle.Captures.CaptureDetails
  alias Chronicle.Connections.Connection
  alias Chronicle.WireResult

  alias Cratis.Chronicle.Contracts.Captures.{
    CapturedEventsRequest,
    Captures,
    DeleteCaptureRequest,
    GetCapturesRequest,
    SaveCaptureRequest,
    StartCaptureRequest,
    StopCaptureRequest,
    ValidateCaptureDeclarationRequest
  }

  @doc """
  Registers (saves) a capture.

  `capture` is a module using `Chronicle.Captures.Capture`. Saving an already-started capture
  fails on the kernel; stop it first.
  """
  @spec register(module(), keyword()) :: {:ok, CaptureDetails.t()} | {:error, term()}
  def register(capture, opts \\ []) when is_atom(capture) do
    with {:ok, channel, config} <- resolve_channel(opts) do
      request =
        struct(SaveCaptureRequest,
          EventStore: config.event_store,
          Id: guid_from_string(capture.__chronicle_capture__(:id)),
          Declaration: capture.__chronicle_capture__(:declaration)
        )

      case Captures.Stub.save_capture(channel, request) do
        {:ok, envelope} ->
          with {:ok, response} <- WireResult.unwrap(envelope) do
            save_capture_result(response)
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp save_capture_result(response) do
    case Map.get(response, :Capture) do
      nil ->
        messages = response |> Map.get(:Messages, []) |> Enum.map(&Map.get(&1, :Message, ""))
        {:error, {:declaration_rejected, messages}}

      capture ->
        {:ok, CaptureDetails.from_proto(capture)}
    end
  end

  @doc "Starts a capture, identified by its module or its capture id."
  @spec start(module() | String.t(), keyword()) :: :ok | {:error, term()}
  def start(capture, opts \\ []) do
    with {:ok, channel, config} <- resolve_channel(opts) do
      request =
        struct(StartCaptureRequest,
          EventStore: config.event_store,
          CaptureId: guid_from_string(capture_id(capture))
        )

      case Captures.Stub.start_capture(channel, request) do
        {:ok, envelope} -> with {:ok, _} <- WireResult.unwrap(envelope), do: :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc "Stops a capture, identified by its module or its capture id."
  @spec stop(module() | String.t(), keyword()) :: :ok | {:error, term()}
  def stop(capture, opts \\ []) do
    with {:ok, channel, config} <- resolve_channel(opts) do
      request =
        struct(StopCaptureRequest,
          EventStore: config.event_store,
          CaptureId: guid_from_string(capture_id(capture))
        )

      case Captures.Stub.stop_capture(channel, request) do
        {:ok, envelope} -> with {:ok, _} <- WireResult.unwrap(envelope), do: :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc "Deletes a capture, identified by its module or its capture id."
  @spec delete(module() | String.t(), keyword()) :: :ok | {:error, term()}
  def delete(capture, opts \\ []) do
    with {:ok, channel, config} <- resolve_channel(opts) do
      request =
        struct(DeleteCaptureRequest,
          EventStore: config.event_store,
          CaptureId: guid_from_string(capture_id(capture))
        )

      case Captures.Stub.delete_capture(channel, request) do
        {:ok, envelope} -> with {:ok, _} <- WireResult.unwrap(envelope), do: :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc "Lists every capture registered for the current event store."
  @spec list(keyword()) :: {:ok, [CaptureDetails.t()]} | {:error, term()}
  def list(opts \\ []) do
    with {:ok, channel, config} <- resolve_channel(opts) do
      request = struct(GetCapturesRequest, EventStore: config.event_store)

      case Captures.Stub.get_captures(channel, request) do
        {:ok, envelope} ->
          with {:ok, data} <- WireResult.unwrap(envelope) do
            {:ok, Enum.map(data || [], &CaptureDetails.from_proto/1)}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Validates a capture declaration against the kernel's CDL compiler, without saving it.

  `capture` is either a module using `Chronicle.Captures.Capture` or raw CDL text.
  """
  @spec validate(module() | String.t(), keyword()) :: {:ok, [String.t()]} | {:error, term()}
  def validate(capture, opts \\ []) do
    with {:ok, channel, config} <- resolve_channel(opts) do
      request =
        struct(ValidateCaptureDeclarationRequest,
          EventStore: config.event_store,
          Declaration: declaration_text(capture)
        )

      case Captures.Stub.validate_capture_declaration(channel, request) do
        {:ok, envelope} ->
          with {:ok, response} <- WireResult.unwrap(envelope) do
            messages = Map.get(response, :Messages, [])
            {:ok, Enum.map(messages || [], &Map.get(&1, :Message, ""))}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc "Reads the private events a capture has appended, most recent first."
  @spec captured_events(String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def captured_events(capture_name, opts \\ []) when is_binary(capture_name) do
    with {:ok, channel, config} <- resolve_channel(opts) do
      request =
        struct(CapturedEventsRequest,
          EventStore: config.event_store,
          CaptureName: capture_name,
          Namespace: Keyword.get(opts, :namespace, config.namespace),
          MaxEvents: Keyword.get(opts, :max_events, 0)
        )

      case Captures.Stub.captured_events(channel, request) do
        {:ok, envelope} ->
          with {:ok, data} <- WireResult.unwrap(envelope) do
            {:ok, data || []}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Registers every discoverable capture.

  Idempotent: skips a capture whose declaration already matches the kernel's. Warns (rather
  than failing) before saving over a started capture whose declaration changed — saving a
  started capture stops it, so it comes back stopped. Starts a capture only when it declares
  `start: true`.
  """
  @spec register_discovered(keyword()) :: :ok | {:error, term()}
  def register_discovered(opts \\ []) do
    modules = capture_modules(opts)

    if Enum.empty?(modules) do
      :ok
    else
      with {:ok, existing} <- list(opts) do
        Enum.reduce_while(modules, :ok, fn module, :ok ->
          case reconcile(module, existing, opts) do
            :ok -> {:cont, :ok}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end)
      end
    end
  end

  defp reconcile(module, existing, opts) do
    id = module.__chronicle_capture__(:id)
    declaration = module.__chronicle_capture__(:declaration)
    current = Enum.find(existing, &(&1.id == id))

    case current do
      %CaptureDetails{declaration: ^declaration} ->
        maybe_start(module, current, opts)

      %CaptureDetails{status: :started} ->
        require Logger

        Logger.warning(
          "Chronicle capture #{inspect(module)} (#{id}) changed while started on the kernel; " <>
            "saving stops it. Restart it manually, or declare `start: true` to have it restarted."
        )

        with {:ok, _} <- register(module, opts), do: maybe_start(module, nil, opts)

      _ ->
        with {:ok, _} <- register(module, opts), do: maybe_start(module, nil, opts)
    end
  end

  defp maybe_start(module, current, opts) do
    cond do
      not module.__chronicle_capture__(:start?) -> :ok
      match?(%CaptureDetails{status: :started}, current) -> :ok
      true -> start(module, opts)
    end
  end

  defp capture_id(capture) when is_atom(capture) and not is_nil(capture) do
    if function_exported?(capture, :__chronicle_capture__, 1) do
      capture.__chronicle_capture__(:id)
    else
      raise ArgumentError, "#{inspect(capture)} is not a discoverable Chronicle capture"
    end
  end

  defp capture_id(capture) when is_binary(capture), do: capture

  defp declaration_text(capture) when is_atom(capture) and not is_nil(capture) do
    capture.__chronicle_capture__(:declaration)
  end

  defp declaration_text(capture) when is_binary(capture), do: capture

  defp capture_modules(opts) do
    case Keyword.get(opts, :captures) do
      captures when is_list(captures) and captures != [] ->
        captures

      _ ->
        case configured_client(opts) do
          %{captures: captures} when is_list(captures) and captures != [] -> captures
          _ -> Artifacts.discover_loaded().captures
        end
    end
  end

  defp configured_client(opts) do
    client = Keyword.get(opts, :client, Chronicle.Client)
    Chronicle.Client.config(client)
  rescue
    _ -> nil
  end

  defp resolve_channel(opts) do
    client = Keyword.get(opts, :client, Chronicle.Client)

    case Chronicle.Client.config(client) do
      config when is_map(config) ->
        case Connection.channel(config.connection) do
          {:ok, channel} -> {:ok, channel, config}
          error -> error
        end

      _ ->
        {:error, :no_client}
    end
  end

  defp guid_from_string(value) do
    normalized = String.replace(value, "-", "")

    <<part1::binary-size(8), part2::binary-size(4), part3::binary-size(4), part4::binary-size(4),
      part5::binary-size(12)>> = normalized

    bytes =
      reverse_binary(Base.decode16!(part1, case: :mixed)) <>
        reverse_binary(Base.decode16!(part2, case: :mixed)) <>
        reverse_binary(Base.decode16!(part3, case: :mixed)) <>
        Base.decode16!(part4 <> part5, case: :mixed)

    <<lo::little-unsigned-64, hi::little-unsigned-64>> = bytes
    struct(BclGuid, lo: lo, hi: hi)
  end

  defp reverse_binary(binary),
    do: binary |> :binary.bin_to_list() |> Enum.reverse() |> :binary.list_to_bin()
end
