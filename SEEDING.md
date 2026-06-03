# Chronicle Seeding

Seeding support for Chronicle.Elixir allows you to pre-populate your event store with initial events during application startup. This is useful for development, testing, and initial production setup.

## Overview

Seeders follow the same pattern as Reactors and Reducers in Chronicle:

1. **Define** a seeder module using `use Chronicle.Seeder`
2. **Implement** the `seed/1` callback to accumulate events
3. **Register** the seeder with `Chronicle.Client`
4. **Auto-discovery** finds seeders automatically when enabled

## Defining a Seeder

```elixir
defmodule MyApp.Seeders.AccountSeeder do
  use Chronicle.Seeder

  alias MyApp.Events.{AccountOpened, FundsDeposited}

  @impl true
  def seed(builder) do
    builder
    |> Chronicle.Seeding.for(
      AccountOpened,
      "seed-account-1",
      [
        %AccountOpened{
          account_id: "seed-account-1",
          owner_name: "Alice",
          initial_balance: 10_000
        }
      ]
    )
    |> Chronicle.Seeding.for(
      FundsDeposited,
      "seed-account-1",
      [
        %FundsDeposited{
          account_id: "seed-account-1",
          amount: 5_000
        }
      ]
    )
  end
end
```

## Builder API

The `Chronicle.Seeding` builder provides three main functions:

### `for/4` - Seed events of a specific type

```elixir
Chronicle.Seeding.for(builder, EventType, "event-source-id", [event1, event2])
```

Adds events of a single type for a given event source (aggregate) ID.

### `for_event_source/3` - Seed multiple event types

```elixir
Chronicle.Seeding.for_event_source(builder, "event-source-id", [
  %AccountOpened{...},
  %FundsDeposited{...}
])
```

Adds events of different types for the same event source.

### `for_namespace/3` - Scope to a namespace

```elixir
Chronicle.Seeding.for_namespace(builder, "production", fn scoped ->
  scoped
  |> Chronicle.Seeding.for(EventType, "event-source-id", [event1])
end)
```

Scopes subsequent events to a specific namespace instead of the global scope.

## Registering Seeders

### Explicit Registration

```elixir
{Chronicle.Client,
  connection_string: "chronicle://localhost:35000",
  event_store: "my-app",
  seeders: [
    MyApp.Seeders.AccountSeeder,
    MyApp.Seeders.ProductSeeder
  ]}
```

### Auto-Discovery

```elixir
{Chronicle.Client,
  connection_string: "chronicle://localhost:35000",
  event_store: "my-app",
  otp_app: :my_app}  # Discovers all seeders in :my_app
```

Auto-discovery is enabled by default and finds all modules using `Chronicle.Seeder`.

## Lifecycle

Seeders execute during `Chronicle.Client` initialization:

1. **Discovery** - Find all seeder modules (explicit + auto-discovered)
2. **Accumulation** - Call each seeder's `seed/1` to populate the builder
3. **Organization** - Group events by global/namespaced, event type, and event source
4. **Registration** - Send all accumulated events to Chronicle in a single batch

## Idempotency

Seeders run every time your application starts. Design your seeders to be idempotent:

- Use event constraints (unique constraints) to prevent duplicate events
- Seed events with stable, deterministic IDs
- Consider conditional seeding based on existing data

## Error Handling

- Failed seeders log a warning but don't prevent application startup
- Other seeders continue executing even if one fails
- The Chronicle client starts normally even if seeding fails

## Best Practices

1. **Keep seeders fast** - They run during startup and block the client initialization
2. **Use stable IDs** - Generate deterministic event source IDs for seed data
3. **Document seed data** - Comment what each seeder provides
4. **Separate concerns** - Create one seeder per domain aggregate or feature
5. **Test seeders** - Verify your seed data loads correctly in tests

## Example: Development Seed Data

```elixir
defmodule MyApp.Seeders.DevelopmentSeeder do
  use Chronicle.Seeder

  @impl true
  def seed(builder) do
    if Mix.env() == :dev do
      builder
      |> seed_admin_user()
      |> seed_test_accounts()
      |> seed_sample_products()
    else
      builder
    end
  end

  defp seed_admin_user(builder) do
    Chronicle.Seeding.for(builder, UserRegistered, "admin-user-1", [
      %UserRegistered{
        user_id: "admin-user-1",
        email: "admin@example.com",
        role: :admin
      }
    ])
  end

  defp seed_test_accounts(builder) do
    Chronicle.Seeding.for_event_source(builder, "test-account-1", [
      %AccountOpened{account_id: "test-account-1", owner_name: "Test User"},
      %FundsDeposited{account_id: "test-account-1", amount: 1000}
    ])
  end

  defp seed_sample_products(builder) do
    products = [
      %ProductCreated{product_id: "prod-1", name: "Widget A", price: 1999},
      %ProductCreated{product_id: "prod-2", name: "Widget B", price: 2999}
    ]

    Enum.reduce(products, builder, fn product, acc ->
      Chronicle.Seeding.for(acc, ProductCreated, product.product_id, [product])
    end)
  end
end
```

## Comparison with Other Clients

### C# Client
```csharp
public class AccountSeeder : ICanSeedEvents
{
    public void Seed(IEventSeedingBuilder builder)
    {
        builder.For<AccountOpened>("seed-account-1", new[] {
            new AccountOpened { /* ... */ }
        });
    }
}
```

### TypeScript Client
```typescript
@seeder()
export class AccountSeeder implements ICanSeedEvents {
    async seed(builder: IEventSeedingBuilder): Promise<void> {
        builder.for(AccountOpened, "seed-account-1", [
            { /* ... */ }
        ]);
    }
}
```

### Elixir Client
```elixir
defmodule AccountSeeder do
  use Chronicle.Seeder

  @impl true
  def seed(builder) do
    builder
    |> Chronicle.Seeding.for(AccountOpened, "seed-account-1", [
      %AccountOpened{...}
    ])
  end
end
```

All three implementations follow the same conceptual model and API surface.
