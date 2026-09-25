---
title: "Context management: correlation, identity, and causation"
description: Set process-scoped correlation ids, identities and causation chains that the Elixir client records with every append.
---

Every event Chronicle stores records which operation it belonged to, who caused it, and the chain of steps that led to it. [Correlation, identity, and causation](/chronicle/concepts/correlation-identity-causation/) explains what the three mean and why Chronicle tracks them. This page covers how you set them from Elixir.

All three live in the calling process's dictionary. Set them once at the start of a request or job, and every append from that process carries them. You can override each one on a single call. Because they are process-scoped, they don't follow work into spawned processes; see [Async/spawn considerations](#asyncspawn-considerations).

## Correlation IDs

A correlation id groups the events that one user action or job produced, so you can trace it across services.

### Creating Correlation IDs

```elixir
alias Chronicle.Correlation.CorrelationId

# A new random UUID-based correlation id
correlation_id = CorrelationId.create()

# Wrap an id you received from elsewhere, such as an incoming request header
correlation_id = CorrelationId.new("92a130f7-16e2-44f7-a8e3-79e76f5df3e1")
```

### Process-Scoped Correlation

Set a correlation id for the process, and every following append includes it:

```elixir
alias Chronicle.Correlation.CorrelationId

Chronicle.set_correlation_id(CorrelationId.create())

:ok = Chronicle.append("account-42", %MyApp.Events.AccountOpened{owner: "Alice", balance: 500})
:ok = Chronicle.append("account-42", %MyApp.Events.FundsDeposited{amount: 100})

# Read the current correlation id
current = Chronicle.current_correlation_id()

# Replace it with a newly generated id before the next operation
Chronicle.clear_correlation_id()
```

`set_correlation_id/1` also accepts a plain string. Two details matter when you rely on the value:

- When no correlation id is set, every call to `current_correlation_id/0`, and every append, gets a **new** random id. Two appends only share a correlation id if you set one.
- `clear_correlation_id/0` doesn't remove the id. It stores and returns a freshly generated one.

### One-Off Correlation Override

Override the process-scoped correlation id for a single append:

```elixir
:ok =
  Chronicle.append("account-42", event,
    correlation_id: "92a130f7-16e2-44f7-a8e3-79e76f5df3e1"
  )
```

## Identity

Identity answers *who caused this state change?* Chronicle stores it with every event, which gives you a permanent record of authorship for audits, debugging, and "last changed by" views.

An identity is a `%Chronicle.Identity{}` with four fields:

| Field | Description |
| --- | --- |
| `subject` | Stable unique identifier, such as a user id from your identity provider |
| `name` | Human-readable display name |
| `user_name` | Login or user name. Defaults to `""`. |
| `on_behalf_of` | The identity this one acts for, or `nil`. See [On-behalf-of / delegation chains](#on-behalf-of--delegation-chains). |

### Creating Identity

```elixir
alias Chronicle.Identity

identity = Identity.new("user-42", "Alice Cooper", "alice")
```

Chronicle also provides three well-known identities:

```elixir
Identity.system()    # automated processes and background work
Identity.not_set()   # identity was deliberately not provided
Identity.unknown()   # identity information could not be determined
```

When a process hasn't set an identity, appends record `Identity.system()`. Set a real identity for anything a person caused, or their actions are recorded as system actions.

### Process-Scoped Identity

Set the identity for the process, and every following append records it:

```elixir
alias Chronicle.Identity

Chronicle.set_identity(Identity.new("user-42", "Alice Cooper", "alice"))

:ok = Chronicle.append("account-42", %MyApp.Events.AccountOpened{owner: "Alice", balance: 500})
:ok = Chronicle.append("account-42", %MyApp.Events.FundsDeposited{amount: 100})

current = Chronicle.current_identity()

Chronicle.clear_identity()
```

### One-Off Identity Override

Override the process-scoped identity for a single append:

```elixir
identity = Identity.new("batch-processor", "Batch Processor", "batch")

:ok = Chronicle.append("account-42", event, identity: identity)
```

### Switching Identity

When one process serves several users, such as a CLI tool, a test harness or an admin console, switch the identity between operations. Chronicle records the identity in effect at each append:

```elixir
alice = Identity.new("u-alice", "Alice Smith", "alice.smith")
bob = Identity.new("u-bob", "Bob Jones", "bob.jones")

# Alice approves a leave request
Chronicle.set_identity(alice)
:ok = Chronicle.append(request_id, %MyApp.Events.LeaveApproved{approved_by: "u-alice"})

# Bob then archives it
Chronicle.set_identity(bob)
:ok = Chronicle.append(request_id, %MyApp.Events.RequestArchived{})
```

The event log shows Alice caused the approval and Bob caused the archival.

### On-Behalf-Of / Delegation Chains

When a system actor performs an action for a person, pass the person as the fourth argument, `on_behalf_of`:

```elixir
alias Chronicle.Identity

human = Identity.new("u-alice", "Alice Smith", "alice.smith")

system_acting =
  Identity.new("s-workflow", "Workflow Engine", "workflow-engine", human)

Chronicle.set_identity(system_acting)
:ok = Chronicle.append("order-99", %MyApp.Events.OrderFulfilled{})
```

Chronicle records the full chain: the workflow engine, acting on behalf of Alice. `Identity.without_duplicates/1` removes repeated subjects from a long chain.

## Causation Chains

Causation records the steps that led to an event: a root, such as an incoming HTTP request, followed by the commands or messages that triggered the change. Chronicle stores the chain with every event, so you can follow an event back to where it started.

### Building Causation Chains

```elixir
alias Chronicle.Auditing.CausationManager

# The root: the action that started the chain
CausationManager.define_root(%{application: "banking-api", version: "1.0"})

# The command this request executes
CausationManager.add("Banking.Commands.OpenAccount", %{account_id: "account-42"})

# Each append stores the full chain
:ok = Chronicle.append("account-42", %MyApp.Events.AccountOpened{owner: "Alice", balance: 500})

# Remove the root and chain before the next operation
CausationManager.clear()
```

### Causation Entries

Each step is a `Chronicle.Auditing.CausationEntry` with a type and a map of properties. The type identifies the operation, typically the full name of a command or message:

```elixir
alias Chronicle.Auditing.CausationManager

CausationManager.define_root(%{request_id: "req-1", source: "my-api"})
CausationManager.add("MyApp.Commands.PlaceOrder", %{order_id: "order-99"})

# A second step triggered by the first
CausationManager.add("MyApp.Commands.ReserveInventory", %{sku: "ABC123", qty: 2})
```

Properties become part of the permanent event log. Don't put secrets or personal data in them.

### One-Off Causation Override

Pass a causation list for a single append:

```elixir
alias Chronicle.Auditing.CausationEntry

causation = [
  CausationEntry.new("MyApp.Commands.InitialRequest", %{request_id: "req-1"}),
  CausationEntry.new("MyApp.Commands.ProcessRequest", %{item_id: "item-1"})
]

:ok = Chronicle.append("resource-42", event, causation: causation)
```

## Typical Usage Pattern

Set the context at the boundary of each request or job, and reset it when the work ends, whether it succeeded or not. Some web servers reuse one process for several requests on a connection, so context left behind can leak into the next request.

This Phoenix controller action is an excerpt: it assumes an authentication plug has put `:current_user` and `:request_id` in `conn.assigns`.

```elixir
defmodule MyAppWeb.AccountController do
  use MyAppWeb, :controller

  alias Chronicle.{Auditing.CausationManager, Correlation.CorrelationId, Identity}

  def create(conn, %{"account_id" => account_id, "owner" => owner}) do
    user = conn.assigns.current_user

    Chronicle.set_correlation_id(CorrelationId.create())
    Chronicle.set_identity(Identity.new(user.id, user.name, user.user_name))
    CausationManager.clear()
    CausationManager.define_root(%{request_id: conn.assigns.request_id})
    CausationManager.add("MyApp.Commands.OpenAccount", %{account_id: account_id})

    try do
      case Chronicle.append(account_id, %MyApp.Events.AccountOpened{owner: owner, balance: 0}) do
        :ok -> send_resp(conn, 201, "")
        {:error, reason} -> send_resp(conn, 422, inspect(reason))
      end
    after
      Chronicle.clear_correlation_id()
      Chronicle.clear_identity()
      CausationManager.clear()
    end
  end
end
```

## Async/Spawn Considerations

Context lives in the process dictionary, so spawned processes, including `Task` processes, don't inherit it. Capture it before spawning and set it again inside:

```elixir
alias Chronicle.Auditing.CausationManager

correlation_id = Chronicle.current_correlation_id()
identity = Chronicle.current_identity()

Task.start(fn ->
  Chronicle.set_correlation_id(correlation_id)
  Chronicle.set_identity(identity)
  CausationManager.define_root(%{source: "background-task"})

  Chronicle.append("account-42", %MyApp.Events.FundsDeposited{amount: 100})
end)
```

## See Also

- `Chronicle.Correlation.CorrelationId`: correlation id value type
- `Chronicle.Correlation.CorrelationIdManager`: process-scoped correlation handling
- `Chronicle.Identity`: identity value type, well-known identities, and `on_behalf_of` chains
- `Chronicle.Identity.IdentityProvider`: process-scoped identity handling
- `Chronicle.Auditing.CausationManager`: process-scoped causation chains
- `Chronicle.Auditing.CausationEntry`: individual causation steps
- `Chronicle.Auditing.CausationType`: built-in causation entry types
