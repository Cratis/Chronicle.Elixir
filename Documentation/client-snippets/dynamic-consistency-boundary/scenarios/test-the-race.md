```elixir
defmodule MyApp.LoanRaceCheck do
  alias Chronicle.EventSequences.EventLog
  alias Chronicle.ReadModels.{DecisionConflict, DecisionReads}
  alias MyApp.Events.MemberLoansLoanTaken
  alias MyApp.ReadModels.MemberLoans

  # Returns true when the guard rejected the second writer. Run it against a test event store
  # that already holds a registered member.
  def second_writer_rejected?(member_id) do
    result =
      Chronicle.decide(fn _unit_of_work ->
        {:ok, _member} = DecisionReads.get(MemberLoans, member_id)

        # A competing writer appends after the read and before the commit. It runs in its own
        # process, so its append goes straight to the event log instead of this unit of work.
        :ok =
          Task.async(fn ->
            EventLog.append(member_id, %MemberLoansLoanTaken{isbn: "978-0-13-468599-1"})
          end)
          |> Task.await()

        EventLog.append(member_id, %MemberLoansLoanTaken{isbn: "978-0-596-52068-7"})
      end)

    match?({:error, %DecisionConflict{}}, result)
  end
end
```
