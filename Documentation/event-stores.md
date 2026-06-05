# Event Store Discovery

Chronicle Elixir provides APIs to query information about available event stores and their namespaces from the Chronicle kernel. This is useful for administrative tasks, multi-tenant applications, and debugging.

## Overview

Event store discovery allows you to:

- List all available event stores on the Chronicle kernel
- List all namespaces within an event store
- Verify that an event store or namespace exists before operating on it

## Getting Event Stores

Query all event store names from the Chronicle kernel:

```elixir
{:ok, stores} = Chronicle.get_event_stores()
# => {:ok, ["my-app", "crm", "analytics"]}
```

This is useful in multi-tenant or multi-application scenarios where you need to discover which event stores are available:

```elixir
case Chronicle.get_event_stores() do
  {:ok, stores} ->
    IO.puts("Available event stores: #{inspect(stores)}")
  {:error, reason} ->
    IO.puts("Failed to get event stores: #{inspect(reason)}")
end
```

## Getting Namespaces

Query all namespaces within an event store:

```elixir
# Use the configured client's event store
{:ok, namespaces} = Chronicle.get_namespaces()
# => {:ok, ["tenant-1", "tenant-2", "tenant-3"]}

# Specify a different event store
{:ok, namespaces} = Chronicle.get_namespaces(event_store: "analytics")
```

This is especially useful in multi-tenant applications:

```elixir
defmodule MyApp.Tenants do
  def list_all_tenants() do
    case Chronicle.get_namespaces() do
      {:ok, tenant_ids} -> tenant_ids
      {:error, _} -> []
    end
  end

  def migrate_all_tenants(migration_func) do
    Enum.each(list_all_tenants(), fn tenant_id ->
      IO.puts("Migrating tenant: #{tenant_id}")
      migration_func.(tenant_id)
    end)
  end
end
```

## Typical Usage

### Multi-Tenant Admin Interface

```elixir
defmodule MyApp.Admin.Dashboard do
  alias MyApp.Tenants

  def get_system_stats() do
    with {:ok, stores} <- Chronicle.get_event_stores(),
         {:ok, namespaces} <- Chronicle.get_namespaces() do
      %{
        event_stores: stores,
        current_store_namespaces: namespaces,
        total_tenants: Enum.count(namespaces)
      }
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def list_tenant_info() do
    with {:ok, tenant_ids} <- Chronicle.get_namespaces() do
      Enum.map(tenant_ids, fn tenant_id ->
        %{
          id: tenant_id,
          event_store: "my-app",
          namespace: tenant_id
        }
      end)
    else
      {:error, reason} -> {:error, reason}
    end
  end
end
```

### Verifying Environment Before Operations

```elixir
defmodule MyApp.Operations do
  def safe_append(tenant_id, event) do
    with {:ok, namespaces} <- Chronicle.get_namespaces() do
      if Enum.member?(namespaces, tenant_id) do
        Chronicle.append("entity-123", event, namespace: tenant_id)
      else
        {:error, :tenant_not_found}
      end
    end
  end

  def safe_read(tenant_id, entity_id) do
    with {:ok, namespaces} <- Chronicle.get_namespaces() do
      if Enum.member?(namespaces, tenant_id) do
        Chronicle.read_model(MyApp.ReadModels.Entity, entity_id, namespace: tenant_id)
      else
        {:error, :tenant_not_found}
      end
    end
  end
end
```

### Multi-Store Operations

```elixir
defmodule MyApp.MultiStore do
  def list_all_entities() do
    with {:ok, stores} <- Chronicle.get_event_stores() do
      Enum.flat_map(stores, fn store_name ->
        case Chronicle.all(MyApp.ReadModels.Entity, client: store_name) do
          {:ok, entities} -> entities
          {:error, _} -> []
        end
      end)
    else
      {:error, _} -> []
    end
  end

  def get_global_stats() do
    with {:ok, stores} <- Chronicle.get_event_stores() do
      Enum.map(stores, fn store_name ->
        with {:ok, namespaces} <- Chronicle.get_namespaces(event_store: store_name) do
          %{
            store: store_name,
            namespace_count: Enum.count(namespaces),
            namespaces: namespaces
          }
        else
          {:error, reason} -> %{store: store_name, error: reason}
        end
      end)
    end
  end
end
```

## Options

Both `get_event_stores/1` and `get_namespaces/1` accept options:

- `:client` — the client name (default: `Chronicle.Client`)
- `:event_store` — for `get_namespaces/1`, the event store to query (defaults to the configured client's event store)

```elixir
# Use a named client
Chronicle.get_event_stores(client: :my_app_client)

# Query a specific event store's namespaces
Chronicle.get_namespaces(event_store: "crm")

# Both
Chronicle.get_namespaces(client: :analytics, event_store: "analytics")
```

## Error Handling

Both functions return `{:ok, list}` on success or `{:error, reason}` on failure:

```elixir
case Chronicle.get_namespaces() do
  {:ok, namespaces} ->
    IO.puts("Namespaces: #{inspect(namespaces)}")
  {:error, reason} ->
    case reason do
      :no_client -> IO.puts("Chronicle.Client not started")
      _ -> IO.puts("Error: #{inspect(reason)}")
    end
end
```

## See Also

- `Chronicle.EventStores` — low-level event store discovery
- `Chronicle` — high-level API
- `README.md` — quick start guide
- Configuration options in `Chronicle.Client`
