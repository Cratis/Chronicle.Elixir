```elixir
defmodule MyApp.Events.MemberLoansMemberRegistered do
  use Chronicle.Events.EventType, id: "member-loans-member-registered"

  defstruct [:name]
end

defmodule MyApp.Events.MemberLoansLoanTaken do
  use Chronicle.Events.EventType, id: "member-loans-loan-taken"

  defstruct [:isbn]
end

defmodule MyApp.Events.MemberLoansLoanReturned do
  use Chronicle.Events.EventType, id: "member-loans-loan-returned"

  defstruct [:isbn]
end

defmodule MyApp.ReadModels.MemberLoans do
  use Chronicle.ReadModels.ReadModel

  defstruct id: nil, active: 0

  from MyApp.Events.MemberLoansMemberRegistered, set: [id: :event_source_id]
  from MyApp.Events.MemberLoansLoanTaken, add: [active: 1]
  from MyApp.Events.MemberLoansLoanReturned, subtract: [active: 1]
end

defmodule MyApp.MemberLoansTakeLoan do
  alias Chronicle.EventSequences.EventLog
  alias Chronicle.ReadModels.{DecisionConflict, DecisionReads}
  alias MyApp.Events.MemberLoansLoanTaken
  alias MyApp.ReadModels.MemberLoans

  @max_active_loans 3

  def handle(member_id, isbn) do
    result =
      Chronicle.decide(fn _unit_of_work ->
        {:ok, member} = DecisionReads.get(MemberLoans, member_id)

        case member.instance do
          nil ->
            :unknown_member

          %MemberLoans{active: active} when active >= @max_active_loans ->
            :limit_reached

          %MemberLoans{} ->
            :ok = EventLog.append(member_id, %MemberLoansLoanTaken{isbn: isbn})
            :taken
        end
      end)

    case result do
      {:ok, outcome} -> outcome
      # Another loan or return was appended for this member after the read. Nothing was appended.
      {:error, %DecisionConflict{}} -> :changed_concurrently
      {:error, _reason} -> :failed
    end
  end
end
```
