# Context Management: Correlation, Identity, and Causation

Chronicle Elixir provides process-scoped context management for tracking correlation, identity, and causation information as you append events. This enables better traceability and auditing across your event-sourced system.

## Overview

Context information includes:

- **Correlation ID** — links related operations together across processes and services
- **Identity** — identifies who caused each state change  
- **Causation** — tracks the chain of operations that led to an event

## Correlation IDs

Correlation IDs group related operations together, making it easy to trace a user action through multiple services.

### Creating Correlation IDs

```elixir
alias Chronicle.CorrelationId

# Generate a new random UUID-based correlation ID
correlation_id = CorrelationId.create()

# Parse a string or UUID as a correlation ID
correlation_id = CorrelationId.parse("92a130f7-16e2-44f7-a8e3-79e76f5df3e1")
```

### Process-Scoped Correlation

Set a correlation ID for your process, and all subsequent `append` calls will include it:

```elixir
alias Chronicle.CorrelationId

# Set for the current process
correlation_id = CorrelationId.create()
Chronicle.set_correlation_id(correlation_id)

# All appends now use this correlation ID
:ok = Chronicle.append("account-42", %MyApp.Events.AccountOpened{...})
:ok = Chronicle.append("account-42", %MyApp.Events.FundsDeposited{...})

# Get the current correlation ID
current = Chronicle.current_correlation_id()

# Clear it when done
Chronicle.clear_correlation_id()
```

### One-Off Correlation Override

For a single append, override the process-scoped correlation ID:

```elixir
:ok = Chronicle.append("account-42", event, 
  correlation_id: "92a130f7-16e2-44f7-a8e3-79e76f5df3e1"
)
```

## Identity

Identity tracks who caused a state change. It includes subject, display name, and username.

### Creating Identity

```elixir
alias Chronicle.Identity

# Create with subject, display name, and username
identity = Identity.new("user-42", "Alice Cooper", "alice")
```

### Process-Scoped Identity

Set identity for your process, and all subsequent appends will include it:

```elixir
alias Chronicle.Identity

identity = Identity.new("user-42", "Alice Cooper", "alice")
Chronicle.set_identity(identity)

# All appends now use this identity
:ok = Chronicle.append("account-42", %MyApp.Events.AccountOpened{...})
:ok = Chronicle.append("account-42", %MyApp.Events.FundsDeposited{...})

# Get the current identity
current = Chronicle.current_identity()

# Clear it when done
Chronicle.clear_identity()
```

### One-Off Identity Override

For a single append, override the process-scoped identity:

```elixir
identity = Identity.new("system", "Batch Processor", "batch")

:ok = Chronicle.append("account-42", event, 
  identity: identity
)
```

## Causation Chains

Causation tracks the chain of operations that led to an event. This is useful for auditing and debugging complex workflows.

### Building Causation Chains

```elixir
alias Chronicle.{CausationManager, CausationEntry, CausationType}

# Define a root cause (the initial action)
CausationManager.define_root(%{application: "banking-api", version: "1.0"})

# Add command that caused the event
CausationManager.add("Banking.Commands.OpenAccount", %{account_id: "account-42"})

# Add another step
CausationManager.add("Banking.Commands.DepositFunds", %{amount: 1000})

# Append events - they will include the causation chain
:ok = Chronicle.append("account-42", %MyApp.Events.AccountOpened{...})
:ok = Chronicle.append("account-42", %MyApp.Events.FundsDeposited{...})

# Clear for next operation
CausationManager.clear()
```

### Causation Types

Causation entries can have a type that describes their role:

```elixir
alias Chronicle.{CausationManager, CausationType}

# Default causation entries have no specific type
CausationManager.add("MyApp.Commands.Process", %{id: "123"})

# You can inspect causation types via CausationType module
```

### One-Off Causation Override

For a single append, override the process-scoped causation chain:

```elixir
alias Chronicle.CausationEntry

causation = [
  CausationEntry.new("MyApp.Commands.InitialRequest", %{request_id: "req-1"}),
  CausationEntry.new("MyApp.Commands.ProcessRequest", %{item_id: "item-1"})
]

:ok = Chronicle.append("resource-42", event, causation: causation)
```

## Typical Usage Pattern

Here's a typical web request handler pattern:

```elixir
defmodule MyApp.Web.AccountController do
  alias Chronicle.{CorrelationId, Identity, CausationManager}

  def open_account(conn, params) do
    # Set up context for this request
    correlation_id = CorrelationId.create()
    Chronicle.set_correlation_id(correlation_id)

    # Identity comes from the authenticated user
    user_id = conn.assigns[:user_id]
    user_name = conn.assigns[:user_name]
    Chronicle.set_identity(Identity.new(user_id, user_name, user_id))

    # Track the command that triggered this
    CausationManager.define_root(%{request_id: conn.assigns[:request_id]})
    CausationManager.add("MyApp.Commands.OpenAccount", %{account_id: params["account_id"]})

    # Append events
    case Chronicle.append(params["account_id"], %MyApp.Events.AccountOpened{...}) do
      :ok ->
        # Clean up context
        Chronicle.clear_correlation_id()
        Chronicle.clear_identity()
        CausationManager.clear()

        send_resp(conn, 201, "Account created")
      {:error, reason} ->
        send_resp(conn, 400, inspect(reason))
    end
  end
end
```

## Async/Spawn Considerations

Context is process-scoped using Elixir's process dictionary. When you spawn a new process, it won't inherit the context from the parent:

```elixir
# Main process
Chronicle.set_correlation_id(correlation_id)

# This spawned process won't have the correlation_id set
spawn(fn ->
  # correlation_id is not set here
  Chronicle.append(...)
end)

# To propagate context, capture and pass it
correlation_id = Chronicle.current_correlation_id()
identity = Chronicle.current_identity()

spawn(fn ->
  Chronicle.set_correlation_id(correlation_id)
  Chronicle.set_identity(identity)
  Chronicle.append(...)
end)
```

## See Also

- `Chronicle.CorrelationId` — correlation ID management
- `Chronicle.CorrelationIdManager` — process-scoped correlation handling
- `Chronicle.Identity` — identity value type
- `Chronicle.IdentityProvider` — process-scoped identity handling
- `Chronicle.CausationManager` — process-scoped causation chain building
- `Chronicle.CausationEntry` — individual causation chain steps
- `Chronicle.CausationType` — causation entry types
- `README.md` — quick start guide
