# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule ConsoleSample.ReadModels.Account do
  @moduledoc """
  Read model representing the current state of a bank account.

  The `from/2` declarations define how Chronicle should project events into this
  model server-side. This is the model-bound projection approach — the projection
  definition lives right next to the struct fields.
  """

  use Chronicle.ReadModel

  alias ConsoleSample.Events.{AccountOpened, FundsDeposited, FundsWithdrawn}

  defstruct account_id: nil, owner_name: nil, balance: 0, transaction_count: 0

  @type t :: %__MODULE__{
          account_id: String.t() | nil,
          owner_name: String.t() | nil,
          balance: number(),
          transaction_count: non_neg_integer()
        }

  from(AccountOpened,
    set: [
      account_id: :event_source_id,
      owner_name: :owner_name,
      balance: :initial_balance
    ]
  )

  from(FundsDeposited,
    add: [balance: :amount],
    count: :transaction_count
  )

  from(FundsWithdrawn,
    subtract: [balance: :amount],
    count: :transaction_count
  )
end
