```elixir
defmodule MyApp.Events.InvoiceNumberInvoiceCreated do
  use Chronicle.Events.EventType, id: "invoice-number-invoice-created"

  defstruct [:number, :customer]
end

# The decision model: the last number issued. Every invoice is created on one numbering event source.
defmodule MyApp.ReadModels.InvoiceNumbering do
  use Chronicle.ReadModels.ReadModel

  defstruct id: nil, last: 0

  from MyApp.Events.InvoiceNumberInvoiceCreated, set: [id: :event_source_id, last: :number]
end

defmodule MyApp.InvoiceNumberCreateInvoice do
  alias Chronicle.EventSequences.EventLog
  alias Chronicle.ReadModels.DecisionReads
  alias MyApp.Events.InvoiceNumberInvoiceCreated
  alias MyApp.ReadModels.InvoiceNumbering

  @numbering_source "invoice-numbering"

  def handle(customer) do
    result =
      Chronicle.decide(fn _unit_of_work ->
        {:ok, numbering} = DecisionReads.get(InvoiceNumbering, @numbering_source)
        next = if numbering.instance, do: numbering.instance.last + 1, else: 1

        # If another invoice was created after the read, the commit is rejected and nothing is written.
        :ok =
          EventLog.append(@numbering_source, %InvoiceNumberInvoiceCreated{
            number: next,
            customer: customer
          })

        next
      end)

    case result do
      {:ok, number} -> number
      {:error, _reason} -> nil
    end
  end
end
```
