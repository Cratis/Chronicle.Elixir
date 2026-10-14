# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.ReadModels.DecisionConflict do
  @moduledoc """
  Raised (by `Chronicle.Transactions.UnitOfWork.with_unit_of_work/2`) or returned as `{:error,
  %DecisionConflict{}}` (by `Chronicle.decide/2`) when a unit of work commits events whose
  enrolled decision reads (`Chronicle.ReadModels.DecisionReads.get/3`) are no longer current:
  something else appended a matching event to one of the guarded event sources between the read
  and the commit. The kernel rejects the whole batch when this happens, so none of the unit of
  work's events were appended.

  `:violations` carries the kernel's raw concurrency violations (see
  `Chronicle.EventSequences.AppendResponse`), one per event source whose guard no longer held.
  """

  defexception violations: []

  @type t :: %__MODULE__{violations: [term()]}

  @impl true
  def message(%__MODULE__{violations: violations}) do
    "A decision read conflicted with a concurrent append: #{inspect(violations)}"
  end
end
