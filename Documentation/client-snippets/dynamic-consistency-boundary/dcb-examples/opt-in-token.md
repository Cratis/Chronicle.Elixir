```elixir
defmodule MyApp.Events.OptInSignUpInitiated do
  use Chronicle.Events.EventType, id: "opt-in-sign-up-initiated"

  defstruct [:email, :token_hash, :expires_at]
end

defmodule MyApp.Events.OptInSignUpConfirmed do
  use Chronicle.Events.EventType, id: "opt-in-sign-up-confirmed"

  defstruct []
end

# Both events live on the sign-up's own event source. The token is checked against the sign-up
# the caller names, so the token itself needs no place in the boundary.
defmodule MyApp.ReadModels.OptInPendingSignUp do
  use Chronicle.ReadModels.ReadModel

  defstruct id: nil, token_hash: nil, expires_at: 0, confirmations: 0

  from MyApp.Events.OptInSignUpInitiated,
    set: [id: :event_source_id, token_hash: :token_hash, expires_at: :expires_at]

  from MyApp.Events.OptInSignUpConfirmed, count: :confirmations
end

defmodule MyApp.OptInConfirmSignUp do
  alias Chronicle.EventSequences.EventLog
  alias Chronicle.ReadModels.{DecisionConflict, DecisionReads}
  alias MyApp.Events.OptInSignUpConfirmed
  alias MyApp.ReadModels.OptInPendingSignUp

  # `expires_at` and `now` are Unix timestamps in seconds.
  def handle(sign_up_id, token_hash, now) do
    result =
      Chronicle.decide(fn _unit_of_work ->
        {:ok, read} = DecisionReads.get(OptInPendingSignUp, sign_up_id)

        cond do
          read.instance == nil ->
            :unknown_sign_up

          read.instance.confirmations > 0 ->
            :already_confirmed

          read.instance.token_hash != token_hash ->
            :wrong_token

          read.instance.expires_at < now ->
            :expired

          true ->
            # Two requests with the same valid token race: the second commit is rejected.
            :ok = EventLog.append(sign_up_id, %OptInSignUpConfirmed{})
            :confirmed
        end
      end)

    case result do
      {:ok, outcome} -> outcome
      {:error, %DecisionConflict{}} -> :changed_concurrently
      {:error, _reason} -> :failed
    end
  end
end
```
