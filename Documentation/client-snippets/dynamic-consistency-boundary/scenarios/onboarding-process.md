```elixir
defmodule MyApp.Events.OnboardingStarted do
  use Chronicle.Events.EventType, id: "onboarding-started"

  defstruct [:email]
end

defmodule MyApp.Events.OnboardingIdentityChecked do
  use Chronicle.Events.EventType, id: "onboarding-identity-checked"

  defstruct [:method]
end

# Appending this event closes the customer's Onboarding stream in the same step.
defmodule MyApp.Events.OnboardingCompleted do
  use Chronicle.Events.EventType, id: "onboarding-completed"

  defstruct []

  closes_stream()
end

# One event source per customer, one stream for the onboarding process. Every writer of the
# stream is guarded against every other, whatever the event type.
defmodule MyApp.OnboardingCustomerEventSource do
  use Chronicle.EventSources.EventSource,
    name: "Customer",
    concurrency: [:event_source_id]

  stream "Onboarding",
    description: "The steps of one customer's onboarding",
    concurrency: [:event_source_id, :event_stream_type]
end

defmodule MyApp.OnboardingProcess do
  alias Chronicle.EventSequences.EventLog
  alias Chronicle.Events.ConstraintViolation
  alias MyApp.Events.{OnboardingCompleted, OnboardingIdentityChecked, OnboardingStarted}
  alias MyApp.OnboardingCustomerEventSource

  def start(customer_id, email), do: step(customer_id, %OnboardingStarted{email: email})

  def check_identity(customer_id, method),
    do: step(customer_id, %OnboardingIdentityChecked{method: method})

  def complete(customer_id) do
    match?({:ok, _}, step(customer_id, %OnboardingCompleted{}))
  end

  # After OnboardingCompleted, any later step is refused with a stream-closed constraint violation.
  def refused_because_closed?({:error, %{constraint_violations: violations}}),
    do: Enum.any?(violations, &Map.has_key?(ConstraintViolation.details(&1), :closed_by))

  def refused_because_closed?(_result), do: false

  defp step(customer_id, event) do
    EventLog.append_with_result(customer_id, event,
      event_source: OnboardingCustomerEventSource,
      event_stream: "Onboarding"
    )
  end
end
```
