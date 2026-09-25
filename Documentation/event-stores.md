---
title: Event store discovery
description: List the event stores on a Chronicle kernel and the namespaces in an event store from the Elixir client.
---

Chronicle Elixir provides APIs to query information about available event stores and their namespaces from the Chronicle kernel. This is useful for administrative tasks, multi-tenant applications, and debugging. See [Event Store](/chronicle/concepts/event-store/) and [Namespaces](/chronicle/concepts/namespaces/) for what these concepts mean and how they relate to multi-tenancy — this page covers the Elixir-specific discovery APIs for listing and verifying them at runtime.

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

`get_event_stores/1` lists every event store on the kernel, but reading from one still goes through a client. The `:client` option on reads and appends names a running `Chronicle.Client`, by the `name:` it was started with; it doesn't accept an event store name. To work with several event stores, start one named client per store and pass that name:

```elixir
children = [
  Supervisor.child_spec(
    {Chronicle.Client, name: :orders, connection_string: connection_string, event_store: "orders"},
    id: :orders
  ),
  Supervisor.child_spec(
    {Chronicle.Client, name: :billing, connection_string: connection_string, event_store: "billing"},
    id: :billing
  )
]

Supervisor.start_link(children, strategy: :one_for_one)
```

Each client needs its own child id, because every `Chronicle.Client` child spec defaults to the same id. Once the clients are running, pass the name to target one:

```elixir
{:ok, orders} = Chronicle.all(MyApp.ReadModels.Order, client: :orders)
```

Namespaces are different: `get_namespaces/1` takes an `:event_store` option directly, so one client can inspect any store:

```elixir
defmodule MyApp.MultiStore do
  def namespace_counts do
    with {:ok, stores} <- Chronicle.get_event_stores() do
      Enum.map(stores, fn store_name ->
        case Chronicle.get_namespaces(event_store: store_name) do
          {:ok, namespaces} -> %{store: store_name, namespace_count: length(namespaces)}
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

Both functions return `{:ok, list}` on success or `{:error, reason}` on failure. `{:error, :not_connected}` means the client hasn't connected yet or is reconnecting; see [Resilience](connections/resilience.md).

```elixir
case Chronicle.get_namespaces() do
  {:ok, namespaces} ->
    IO.puts("Namespaces: #{inspect(namespaces)}")

  {:error, :not_connected} ->
    IO.puts("Chronicle is not connected yet")

  {:error, reason} ->
    IO.puts("Error: #{inspect(reason)}")
end
```

Passing a `:client` name that no running client uses raises `ArgumentError` (`no persistent term stored with this key`) instead of returning an error tuple.

## See Also

- `Chronicle.EventStores` — low-level event store discovery
- `Chronicle` — high-level API
- [Get started](get-started.md): install the client and start `Chronicle.Client`
- `Chronicle.Client`: client configuration options
- [Event Store](/chronicle/concepts/event-store/) and [Namespaces](/chronicle/concepts/namespaces/) — the shared concepts behind event stores and namespace-scoped tenancy
