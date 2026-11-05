# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Observers.PartitionNotInBatch do
  @moduledoc """
  Raised when a batch function fails or defers a partition the batch does not hold.
  """

  defexception [:message, :partition]

  @impl true
  def exception(opts) do
    partition = Keyword.fetch!(opts, :partition)

    %__MODULE__{
      partition: partition,
      message:
        "Partition '#{partition}' is not in this batch, so it cannot be failed or deferred."
    }
  end
end
