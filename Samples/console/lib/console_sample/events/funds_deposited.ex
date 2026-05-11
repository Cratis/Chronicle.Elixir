# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule ConsoleSample.Events.FundsDeposited do
  @moduledoc "Emitted when funds are deposited into an account."

  use Chronicle.EventType, id: "funds-deposited"

  defstruct account_id: nil, amount: 0

  @type t :: %__MODULE__{
          account_id: String.t(),
          amount: number()
        }
end
