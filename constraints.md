# Model-Bound Constraints

Chronicle Elixir supports declaring constraints directly on event types using model-bound constraint attributes. These constraints are automatically registered with Chronicle during client startup.

## Overview

Constraints ensure data consistency by enforcing rules about which events can be appended. There are three types of model-bound constraints:

- **Unique constraint** — ensures uniqueness across specified event fields within a scope
- **Unique event type constraint** — ensures at most one event of this type per event source  
- **Remove constraint** — specifies which event type removes a previous constraint

## Declaring Constraints

### Unique Constraint

Use `@unique` to declare that one or more event fields must be unique:

```elixir
defmodule MyApp.Events.UserRegistered do
  use Chronicle.EventType, id: "user-registered-v1"
  defstruct [:email, :tenant_id]

  @unique [:email, :tenant_id]
  unique_event_type()
end
```

The `@unique` attribute can be a single field or a list of fields. Fields are checked for uniqueness across all instances of that event type.

### Unique Event Type Constraint

Use `@unique_event_type` (or `unique_event_type()` macro) to ensure at most one event of this type exists per event source:

```elixir
defmodule MyApp.Events.AccountClosed do
  use Chronicle.EventType, id: "account-closed-v1"
  defstruct [:account_id, :reason]

  @unique_event_type
  unique_event_type()
end
```

This is useful for events that should only happen once per aggregate, like account closure.

### Remove Constraint

Use `@remove_constraint` to specify that appending this event removes a previous constraint:

```elixir
defmodule MyApp.Events.UserDeleted do
  use Chronicle.EventType, id: "user-deleted-v1"
  defstruct [:email]

  @remove_constraint "email"
end
```

When a `UserDeleted` event is appended, any unique constraint named `"email"` is removed, allowing the same email to be registered again.

## Automatic Discovery

Constraints declared on event types are automatically discovered and registered when `Chronicle.Client` starts:

```elixir
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      {Chronicle.Client,
        connection_string: "chronicle://localhost:35000?disableTls=true",
        event_store: "my-app",
        otp_app: :my_app}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```

The client will:
1. Discover all event types in your OTP app
2. Extract constraint metadata via `__chronicle_event_type__(:constraints)`
3. Register all constraints with the Chronicle kernel

## Macro Alternatives

Instead of attributes, you can use macros:

```elixir
defmodule MyApp.Events.UserRegistered do
  use Chronicle.EventType, id: "user-registered-v1"
  defstruct [:email]

  unique([:email])
  unique_event_type()
end
```

Both approaches are equivalent. Use whichever is more readable for your use case.

## Constraint Names

Constraint names are automatically derived from field names or explicitly specified:

```elixir
# Automatic name: "email"
@unique [:email]
unique_event_type()

# Explicit name with macro options:
unique([:email], name: "user-email-unique")
```

When using `@remove_constraint`, the name must match the constraint you want to remove.

## Example: Multi-Tenant Email Uniqueness

```elixir
defmodule BankingApp.Events.CustomerAdded do
  use Chronicle.EventType, id: "customer-added-v1"
  defstruct [:email, :tenant_id]

  # Email must be unique per tenant
  @unique [:email, :tenant_id]
  unique_event_type()
end

defmodule BankingApp.Events.CustomerRemoved do
  use Chronicle.EventType, id: "customer-removed-v1"
  defstruct [:email]

  # Removing a customer also removes the email uniqueness constraint
  @remove_constraint "email"
end
```

## Error Handling

When appending an event that violates a constraint, Chronicle returns an error. The error details come from the Chronicle kernel and will be wrapped in the standard `{:error, reason}` tuple returned by `Chronicle.append/3`.

```elixir
case Chronicle.append("customer-123", %MyApp.Events.CustomerAdded{
  email: "alice@example.com",
  tenant_id: "tenant-1"
}) do
  :ok -> 
    IO.puts("Customer added")
  {:error, reason} ->
    IO.puts("Failed: #{inspect(reason)}")
end
```

## See Also

- `Chronicle.EventType` — declaring event types with constraints
- `Chronicle.Constraints` — low-level constraint registration
- `README.md` — quick start guide with constraints example
