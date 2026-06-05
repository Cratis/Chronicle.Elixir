# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule ConsoleSample.Events.AccountOpened do
  @moduledoc """
  Current generation of the account-opened event.

  Generation 2 adds `account_tier`. The console sample still appends the legacy
  generation 1 event to demonstrate Chronicle upcasting it through the
  registered migration.
  """

  use Chronicle.EventType, id: "account-opened", generation: 2

  unique_event_type()

  defstruct account_id: nil, full_name: nil, initial_balance: 0, account_tier: "standard"

  @type t :: %__MODULE__{
          account_id: String.t(),
          full_name: String.t(),
          initial_balance: number(),
          account_tier: String.t()
        }
end
