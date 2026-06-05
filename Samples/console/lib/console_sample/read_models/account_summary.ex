# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule ConsoleSample.ReadModels.AccountSummary do
  @moduledoc """
  Read model representing account state built by the `AccountReducer`.

  This is the reducer-backed version of the account read model. Unlike the
  projection-backed `Account` model, the reducer calls back into the client
  process for each event batch, which lets you apply arbitrary Elixir logic
  before returning the new state to Chronicle for storage.
  """

  use Chronicle.ReadModel

  defstruct account_id: nil, full_name: nil, account_tier: nil, balance: 0, transaction_count: 0

  @type t :: %__MODULE__{
          account_id: String.t() | nil,
          full_name: String.t() | nil,
          account_tier: String.t() | nil,
          balance: number(),
          transaction_count: non_neg_integer()
        }
end
