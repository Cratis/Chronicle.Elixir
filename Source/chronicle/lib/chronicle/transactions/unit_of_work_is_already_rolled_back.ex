# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Transactions.UnitOfWorkIsAlreadyRolledBack do
  @moduledoc """
  Raised when a rolled back unit of work is mutated or rolled back again.
  """

  defexception message: "unit of work has already been rolled back"
end
