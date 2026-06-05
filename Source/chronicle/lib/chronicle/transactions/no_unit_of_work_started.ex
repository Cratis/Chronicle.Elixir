# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Transactions.NoUnitOfWorkStarted do
  @moduledoc """
  Raised when transaction-scoped APIs are used without an active unit of work.
  """

  defexception message: "no unit of work has been started"
end
