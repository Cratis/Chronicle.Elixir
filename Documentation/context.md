# Context Management: Correlation, Identity, and Causation

Chronicle Elixir provides process-scoped context management for tracking correlation, identity, and causation information as you append events. See [Correlation, identity, and causation](/chronicle/concepts/correlation-identity-causation/) for what these three mean and why Chronicle tracks them. This page covers the Elixir-specific API in depth.

All three are process-scoped: set them once at the start of a request or operation and every subsequent `append` call in the same process will include them automatically. You can always override on a per-call basis.

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

Identity answers the question: *who caused this state change?* It is stored with every event appended to the Chronicle event log, giving you a permanent, queryable record of authorship. This is essential for compliance, debugging, and building audit UIs that show "last changed by".

An identity has three fields:

| Field | Description |
| --- | --- |
| `subject` | Stable unique identifier (e.g. a user UUID from your identity provider) |
| `name` | Human-readable display name |
| `user_name` | Login / username |

### Creating Identity

```elixir
alias Chronicle.Identity

# Create with subject, display name, and username
identity = Identity.new("user-42", "Alice Cooper", "alice")
```

Chronicle also provides three sentinel identities for well-known cases:

```elixir
Identity.system()    # automated processes or background workers
Identity.not_set()   # identity was not provided (default when none is set)
Identity.unknown()   # identity information could not be determined
```

### Process-Scoped Identity

Set identity for your process, and all subsequent appends will include it automatically:

```elixir
alias Chronicle.Identity

identity = Identity.new("user-42", "Alice Cooper", "alice")
Chronicle.set_identity(identity)

# All appends now record Alice as the causer
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

### Switching Identity

In applications where a single process serves multiple users (e.g. a CLI tool, a test harness, or an admin console), you can switch the process-scoped identity between operations. Chronicle records the identity at the moment of each `append`, so different events in the same process can record different causers:

```elixir
alice = Identity.new("u-alice", "Alice Smith", "alice.smith")
bob   = Identity.new("u-bob",   "Bob Jones",   "bob.jones")

# Alice approves a leave request
Chronicle.set_identity(alice)
:ok = Chronicle.append(request_id, %LeaveApproved{approved_by: "u-alice"})

# Bob then archives it
Chronicle.set_identity(bob)
:ok = Chronicle.append(request_id, %RequestArchived{})
```

The event log now shows Alice caused the approval and Bob caused the archival, even though both happened in the same process.

### On-Behalf-Of / Delegation Chains

When a system actor performs an action on behalf of a human user, you can express this as a delegation chain. The `on_behalf_of` field links the acting identity to the originating identity:

```elixir
alias Chronicle.Identity

# The human who initiated the request
human = Identity.new("u-alice", "Alice Smith", "alice.smith")

# The system process acting on her behalf
system_acting = Identity.new(
  "s-workflow",
  "Workflow Engine",
  "workflow-engine",
  human  # on_behalf_of
)

Chronicle.set_identity(system_acting)
:ok = Chronicle.append("order-99", %OrderFulfilled{})
```

Chronicle records the full chain: "Workflow Engine (on behalf of Alice Smith)". Use `Identity.without_duplicates/1` if you need to deduplicate subjects in a long chain.

## Causation Chains

Causation tracks the sequence of operations that led to an event. Each entry in the chain represents one step — a root action (e.g. an incoming HTTP request), followed by the commands or messages that triggered subsequent state changes. This chain is stored with every event, giving you a navigable audit trail you can replay forward from any point.

### Building Causation Chains

```elixir
alias Chronicle.Auditing.CausationManager

# Define the root cause (the initial action that started the chain)
CausationManager.define_root(%{application: "banking-api", version: "1.0"})

# Add the command that this request is executing
CausationManager.add("Banking.Commands.OpenAccount", %{account_id: "account-42"})

# Append events — each one is stored with the full causation chain
:ok = Chronicle.append("account-42", %MyApp.Events.AccountOpened{...})
:ok = Chronicle.append("account-42", %MyApp.Events.FundsDeposited{...})

# Clear for the next operation
CausationManager.clear()
```

### Causation Entries

Each entry in the chain is a `Chronicle.Auditing.CausationEntry` with a type and a map of properties. The type can be any string that identifies the operation — typically a fully-qualified command or message name:

```elixir
alias Chronicle.Auditing.CausationManager

# Root entry with metadata about the originating context
CausationManager.define_root(%{request_id: "req-1", source: "my-api"})

# Command step
CausationManager.add("MyApp.Commands.PlaceOrder", %{order_id: "order-99"})

# A second command triggered by the first (translation / saga step)
CausationManager.add("MyApp.Commands.ReserveInventory", %{sku: "ABC123", qty: 2})
```

### One-Off Causation Override

For a single append, pass a causation list directly:

```elixir
alias Chronicle.Auditing.CausationEntry

causation = [
  CausationEntry.new("MyApp.Commands.InitialRequest", %{request_id: "req-1"}),
  CausationEntry.new("MyApp.Commands.ProcessRequest", %{item_id: "item-1"})
]

:ok = Chronicle.append("resource-42", event, causation: causation)
```

## Typical Usage Pattern

Set up correlation, identity, and causation at the boundary of each request or operation. All appends inside that boundary inherit the context automatically.

```elixir
defmodule MyApp.Web.AccountController do
  alias Chronicle.{CorrelationId, Identity, Auditing.CausationManager}

  def open_account(conn, params) do
    # --- Set up request context ---
    Chronicle.set_correlation_id(CorrelationId.create())
    Chronicle.set_identity(Identity.new(
      conn.assigns[:user_id],
      conn.assigns[:user_display_name],
      conn.assigns[:user_name]
    ))

    CausationManager.clear()
    CausationManager.define_root(%{request_id: conn.assigns[:request_id]})
    CausationManager.add("MyApp.Commands.OpenAccount", %{account_id: params["account_id"]})

    # --- Execute the operation ---
    case Chronicle.append(params["account_id"], %MyApp.Events.AccountOpened{...}) do
      :ok ->
        # --- Clean up ---
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

Context is process-scoped using Elixir's process dictionary. Spawned processes do not inherit context from their parent — capture and pass it explicitly:

```elixir
# Capture before spawning
correlation_id = Chronicle.current_correlation_id()
identity = Chronicle.current_identity()

spawn(fn ->
  Chronicle.set_correlation_id(correlation_id)
  Chronicle.set_identity(identity)
  Chronicle.append(...)
end)
```

## See Also

- `Chronicle.CorrelationId` — correlation ID value type and parsing
- `Chronicle.Correlation.CorrelationIdManager` — process-scoped correlation handling
- `Chronicle.Identity` — identity value type, sentinel values, and `on_behalf_of` chains
- `Chronicle.Identity.IdentityProvider` — process-scoped identity handling
- `Chronicle.Auditing.CausationManager` — process-scoped causation chain building
- `Chronicle.Auditing.CausationEntry` — individual causation chain steps
- `Chronicle.Auditing.CausationType` — built-in causation entry type constants
