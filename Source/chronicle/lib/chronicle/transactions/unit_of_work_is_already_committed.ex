# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Transactions.UnitOfWorkIsAlreadyCommitted do
  @moduledoc """
  Raised when a committed unit of work is mutated or committed again.
  """

  defexception message: "unit of work has already been committed"
end
