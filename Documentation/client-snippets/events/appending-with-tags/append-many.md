```elixir
defmodule MyApp.Events.TaggedMoneyWithdrawn do
  use Chronicle.Events.EventType, id: "tagged-money-withdrawn"

  defstruct [:amount]
end

defmodule MyApp.Events.TaggedWithdrawalFeeCharged do
  use Chronicle.Events.EventType, id: "tagged-withdrawal-fee-charged"

  defstruct [:amount]
end

defmodule MyApp.TaggedWithdrawalService do
  alias MyApp.Events.TaggedMoneyWithdrawn
  alias MyApp.Events.TaggedWithdrawalFeeCharged

  def withdraw(account_id, amount, fee) do
    Chronicle.append_many(
      account_id,
      [
        %TaggedMoneyWithdrawn{amount: amount},
        %TaggedWithdrawalFeeCharged{amount: fee}
      ],
      tags: ["withdrawal", "audit"]
    )
  end
end
```
