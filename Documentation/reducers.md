# Reducers

A reducer folds a stream of events into a read model. Where a projection
describes *what* to map declaratively, a reducer lets you compute the next state
in plain Elixir — useful when the transformation needs logic that a declarative
projection cannot express.

## Defining a reducer

Use `Chronicle.Reducers.Reducer`, point it at a read model with `model:`,
declare the events it handles with `@handles`, and implement `reduce/3`. Each
clause receives the event, the current model (`nil` on first event), and a
context map, and returns the new model:

```elixir
defmodule MyApp.Reducers.AccountReducer do
  use Chronicle.Reducers.Reducer, model: MyApp.ReadModels.Account

  alias MyApp.Events.{AccountOpened, FundsDeposited, FundsWithdrawn}
  alias MyApp.ReadModels.Account

  @handles AccountOpened
  @handles FundsDeposited
  @handles FundsWithdrawn

  @impl true
  def reduce(%AccountOpened{} = event, _model, context) do
    %Account{id: context.event_source_id, owner: event.owner_name, balance: 0}
  end

  def reduce(%FundsDeposited{} = event, model, _context) do
    %{model | balance: model.balance + event.amount}
  end

  def reduce(%FundsWithdrawn{} = event, model, _context) do
    %{model | balance: model.balance - event.amount}
  end
end
```

The context map provides `:event_source_id`, `:sequence_number`, and
`:occurred`, so you can stamp identity and timestamps onto the model.

## Registering a reducer

Reducers are discovered automatically with `otp_app:`, or listed explicitly:

```elixir
{Chronicle.Client,
  connection_string: "chronicle://localhost:35000?disableTls=true",
  event_store: "store",
  reducers: [MyApp.Reducers.AccountReducer],
  read_models: [MyApp.ReadModels.Account]}
```

## Registration ordering matters

A reducer writes into a read model, so the kernel must know about that read
model *before* the reducer's observation stream attaches. The client guarantees
this: it registers read models and reducer definitions first, and only then
lets reducers attach — on the `:registered` phase of the connection lifecycle.
This ordering holds on every reconnect, so reducers recover cleanly after a
kernel restart. See
[Resilience and the Connection Lifecycle](connections/resilience.md).

## Reducer or projection?

Reach for a declarative projection when the mapping is a straightforward
set/add/count over event properties. Reach for a reducer when computing the next
state needs branching, derived values, or logic that reads more naturally as
code.
