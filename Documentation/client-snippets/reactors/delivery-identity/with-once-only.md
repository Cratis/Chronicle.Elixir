```elixir
defmodule CustomerWelcomed do
  use Chronicle.Events.EventType, id: "customer-welcomed"

  defstruct [:customer_id]
end

defmodule WelcomeMail do
  def send(_customer_id), do: :ok
end

defmodule WelcomeMailerReceipts do
  def completed?(_delivery_id), do: false
  def complete(_delivery_id), do: :ok
end

defmodule WelcomeMailer do
  # Skip CustomerWelcomed while the observer replays. Replay exclusion is not
  # exactly-once: recovering a failed partition can still deliver it again,
  # so the delivery receipt guards the side effect as well.
  use Chronicle.Reactors.Reactor, once_only: [CustomerWelcomed]

  @handles CustomerWelcomed

  @impl true
  def handle(%CustomerWelcomed{} = event, %{delivery_id: delivery_id}) do
    if WelcomeMailerReceipts.completed?(delivery_id) do
      :ok
    else
      with :ok <- WelcomeMail.send(event.customer_id) do
        WelcomeMailerReceipts.complete(delivery_id)
      end
    end
  end
end
```
