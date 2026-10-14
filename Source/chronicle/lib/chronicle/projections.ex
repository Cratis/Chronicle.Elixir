# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Projections do
  @moduledoc """
  Idiomatic Elixir interface for ad-hoc projection querying and waiting for a registered
  projection to catch up.

  `query/2` sends a Projection Declaration Language (PDL) string straight to the kernel and
  returns the projected entries, without registering a permanent projection or defining a read
  model module. `preview/2` does the same for an already-registered projection's own
  declaration. Mirrors the C# client's `IProjections.Query()`.

  :::caution
  Every call replays events from the beginning of the event sequence, up to an internal kernel
  limit. Use this for tooling, diagnostics and tests over small, bounded event volumes - not in
  a high-throughput code path.
  :::

  ## Ad-hoc querying

      {:ok, result} =
        Chronicle.Projections.query(\"\"\"
        projection OrderSummary
          from OrderPlaced
        \"\"\")

      result.instances      # decoded as plain maps unless `:read_model` is given
      result.total_count

  Pass `:read_model` to decode the entries as a struct instead of plain maps:

      {:ok, result} = Chronicle.Projections.query(declaration, read_model: MyApp.ReadModels.Order)

  A declaration with syntax or type errors returns
  `{:error, {:invalid_declaration, [%{message: ..., line: ..., column: ...}]}}`.

  ## Previewing a registered projection

      {:ok, result} = Chronicle.Projections.preview(MyApp.ReadModels.Order)

  Looks up the declaration already registered for the read model (or projection identifier) and
  runs it the same way `query/2` does. Returns `{:error, {:unknown_projection, id}}` when no
  declaration is registered under that identifier.

  ## Waiting for a projection

      :ok = Chronicle.Projections.wait_for(MyApp.ReadModels.Order, sequence_number)

  Polls the projection's observer state until it has handled at least `sequence_number`, or
  returns `{:error, :timeout}`.

  ## Common options

    * `:client` — the client name (default: `Chronicle.Client`)
    * `:namespace` — overrides the client's configured namespace
    * `:event_sequence_id` — event sequence identifier (default: `"event-log"`)
  """

  alias Chronicle.Connections.Connection
  alias Chronicle.ReadModels.QueryResult

  alias Cratis.Chronicle.Contracts.Projections.{
    GetAllDeclarationsRequest,
    PreviewProjectionRequest,
    Projections
  }

  @event_log_id "event-log"
  @default_wait_timeout 5_000
  @default_wait_interval 50

  @doc """
  Queries a PDL declaration against the event log without registering it.

  The declaration may omit `=> ReadModelType`, in which case the read model schema is inferred
  from the events it uses; an inferred declaration can never be saved as a permanent projection.

  Returns `{:ok, %Chronicle.ReadModels.QueryResult{}}`, or
  `{:error, {:invalid_declaration, [%{message: String.t(), line: integer(), column: integer()}]}}`
  when the declaration has syntax or type errors.

  ## Options

    * `:read_model` — decode each entry as this struct instead of a plain map
    * (see module documentation for the common options)
  """
  @spec query(String.t(), keyword()) ::
          {:ok, QueryResult.t()} | {:error, {:invalid_declaration, [map()]}} | {:error, term()}
  def query(declaration, opts \\ []) when is_binary(declaration) do
    with {:ok, channel, config} <- resolve_channel(opts) do
      request =
        struct(PreviewProjectionRequest,
          EventStore: config.event_store,
          Namespace: Keyword.get(opts, :namespace, config.namespace),
          EventSequenceId: Keyword.get(opts, :event_sequence_id, @event_log_id),
          Declaration: declaration
        )

      case Projections.Stub.preview(channel, request) do
        {:ok, response} -> decode_preview(response, Keyword.get(opts, :read_model))
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc """
  Looks up the declaration already registered for a read model or projection identifier, and
  runs it through `query/2`.

  Returns `{:error, {:unknown_projection, module_or_id}}` when no declaration is registered under
  that identifier.

  ## Options

  Accepts `:read_model` like `query/2` (defaults to `module_or_id` when it is a module), plus the
  common options.
  """
  @spec preview(module() | String.t(), keyword()) ::
          {:ok, QueryResult.t()}
          | {:error, {:invalid_declaration, [map()]}}
          | {:error, {:unknown_projection, module() | String.t()}}
          | {:error, term()}
  def preview(module_or_id, opts \\ []) do
    with {:ok, channel, config} <- resolve_channel(opts) do
      id = projection_id(module_or_id)
      request = struct(GetAllDeclarationsRequest, EventStore: config.event_store)

      case Projections.Stub.get_all_declarations(channel, request) do
        {:ok, response} ->
          case Enum.find(Map.get(response, :items, []), &(Map.get(&1, :Identifier) == id)) do
            nil ->
              {:error, {:unknown_projection, module_or_id}}

            %{Declaration: declaration} ->
              opts = Keyword.put_new(opts, :read_model, read_model_for(module_or_id))
              query(declaration, opts)
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Waits until the projection that maintains `module_or_id` has handled at least
  `sequence_number`, polling `Chronicle.Observers.get_all/1`.

  Returns `:ok`, or `{:error, :timeout}` once `:timeout` (default `#{@default_wait_timeout}` ms)
  elapses.

  ## Options

    * `:timeout` — maximum time to wait in milliseconds (default `#{@default_wait_timeout}`)
    * `:interval` — delay between polls in milliseconds (default `#{@default_wait_interval}`)
    * (see module documentation for the common options)
  """
  @spec wait_for(module() | String.t(), non_neg_integer(), keyword()) :: :ok | {:error, :timeout}
  def wait_for(module_or_id, sequence_number, opts \\ []) do
    id = projection_id(module_or_id)
    timeout = Keyword.get(opts, :timeout, @default_wait_timeout)
    interval = Keyword.get(opts, :interval, @default_wait_interval)
    deadline = System.monotonic_time(:millisecond) + timeout

    poll_until_handled(id, sequence_number, deadline, interval, opts)
  end

  defp poll_until_handled(id, sequence_number, deadline, interval, opts) do
    reached? =
      case Chronicle.Observers.get_all(opts) do
        {:ok, observers} ->
          Enum.find_value(observers, false, fn observer ->
            observer.id == id and observer.last_handled_event_sequence_number >= sequence_number
          end)

        {:error, _reason} ->
          false
      end

    cond do
      reached? ->
        :ok

      System.monotonic_time(:millisecond) >= deadline ->
        {:error, :timeout}

      true ->
        Process.sleep(interval)
        poll_until_handled(id, sequence_number, deadline, interval, opts)
    end
  end

  defp decode_preview(%{Value1: %{Errors: errors}}, _read_model) when errors not in [nil, []] do
    {:error, {:invalid_declaration, Enum.map(errors, &decode_syntax_error/1)}}
  end

  defp decode_preview(%{Value0: preview}, read_model) when not is_nil(preview) do
    entries =
      preview
      |> Map.get(:ReadModelEntries, [])
      |> Enum.map(&decode_entry(&1, read_model))

    {:ok,
     %QueryResult{
       instances: entries,
       total_count: length(entries),
       page: 0,
       page_size: length(entries)
     }}
  end

  defp decode_preview(_response, _read_model),
    do: {:ok, %QueryResult{instances: [], total_count: 0, page: 0, page_size: 0}}

  defp decode_syntax_error(error) do
    %{
      message: Map.get(error, :Message, ""),
      line: Map.get(error, :Line, 0),
      column: Map.get(error, :Column, 0)
    }
  end

  defp decode_entry(json, nil), do: Jason.decode!(json)

  defp decode_entry(json, model_module),
    do: Chronicle.Serialization.decode(model_module, json, :identity)

  defp projection_id(module) when is_atom(module) do
    cond do
      function_exported?(module, :__chronicle_read_model__, 1) ->
        module.__chronicle_read_model__(:id)

      function_exported?(module, :__chronicle_projection__, 1) ->
        module.__chronicle_projection__(:id)

      true ->
        raise ArgumentError,
              "#{inspect(module)} is not a Chronicle read model or projection module"
    end
  end

  defp projection_id(id) when is_binary(id), do: id

  defp read_model_for(module) when is_atom(module) do
    cond do
      function_exported?(module, :__chronicle_read_model__, 1) ->
        module

      function_exported?(module, :__chronicle_projection__, 1) ->
        module.__chronicle_projection__(:model)

      true ->
        nil
    end
  end

  defp read_model_for(_id), do: nil

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
end
