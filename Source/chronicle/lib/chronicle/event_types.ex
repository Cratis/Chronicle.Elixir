# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.EventTypes do
  @moduledoc """
  Registers event types with a Chronicle event store.

  Called automatically by `Chronicle.Projections.Registrar` during startup.
  You can also call it directly to register event types at runtime.

  ## Example

      {:ok, channel} = Chronicle.Connections.Connection.channel(:my_conn)
      :ok = Chronicle.EventTypes.register(channel, "my-store", [MyApp.Events.AccountOpened])
  """

  alias Cratis.Chronicle.Contracts.Events.{
    EventTypes,
    RegisterEventTypesRequest,
    EventTypeRegistration,
    EventType
  }

  @doc """
  Registers a list of event type modules with Chronicle.

  Each module must `use Chronicle.EventType`. Generates a minimal JSON schema
  for each event type based on its struct fields.

  Returns `:ok` on success or `{:error, reason}` on failure.
  """
  @spec register(term(), String.t(), [module()]) :: :ok | {:error, term()}
  def register(_channel, _event_store, []), do: :ok

  def register(channel, event_store, event_type_modules) when is_list(event_type_modules) do
    registrations =
      Enum.map(event_type_modules, fn module ->
        struct(EventTypeRegistration,
          Type:
            struct(EventType,
              Id: module.__chronicle_event_type__(:id),
              Generation: module.__chronicle_event_type__(:generation)
            ),
          Schema: generate_schema(module),
          EventStore: event_store
        )
      end)

    request =
      struct(RegisterEventTypesRequest,
        EventStore: event_store,
        Types: registrations,
        DisableValidation: false
      )

    case EventTypes.Stub.register(channel, request) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp generate_schema(module) do
    fields =
      if function_exported?(module, :__struct__, 0) do
        module.__struct__()
        |> Map.to_list()
        |> Enum.reject(fn {k, _} -> k == :__struct__ end)
        |> Enum.map(fn {key, default_val} ->
          camel_key = key |> Atom.to_string() |> snake_to_camel()
          {camel_key, event_property_schema(default_val)}
        end)
        |> Map.new()
      else
        %{}
      end

    Jason.encode!(%{"type" => "object", "properties" => fields})
  end

  # Use "number" without format: typeFormats.IsKnown(nil) returns false, so
  # ConvertJsonValueFromUnknownFormat is called with type=Number, which calls
  # GetValue<double>() — the only path that works for JsonElement-backed JSON numbers.
  defp event_property_schema(v) when is_integer(v), do: %{"type" => "number"}
  defp event_property_schema(v) when is_float(v), do: %{"type" => "number"}
  defp event_property_schema(v) when is_boolean(v), do: %{"type" => "boolean"}
  defp event_property_schema(_), do: %{"type" => "string"}

  defp snake_to_camel(snake) do
    [head | tail] = String.split(snake, "_")
    head <> Enum.map_join(tail, &String.capitalize/1)
  end
end
