# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Observers.PartitionFailedInBatch do
  @moduledoc """
  The reason recorded for a partition a batch function failed without giving a reason.
  """

  defexception [:message, :partition]

  @impl true
  def exception(opts) do
    partition = Keyword.fetch!(opts, :partition)

    %__MODULE__{
      partition: partition,
      message: "A batch function failed partition '#{partition}'."
    }
  end
end
