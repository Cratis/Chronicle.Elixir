# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule ConsoleSample.Events.LegacyAccountOpened do
  @moduledoc "Legacy generation of the account-opened event used by the migration demo."

  use Chronicle.EventType, id: "account-opened", generation: 1

  unique_event_type()

  defstruct account_id: nil, owner_name: nil, initial_balance: 0

  @type t :: %__MODULE__{
          account_id: String.t(),
          owner_name: String.t(),
          initial_balance: number()
        }
end
