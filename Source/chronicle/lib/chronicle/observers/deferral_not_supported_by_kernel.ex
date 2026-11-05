# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Observers.DeferralNotSupportedByKernel do
  @moduledoc """
  The reason a deferred partition fails when the kernel did not deliver a page.

  A kernel that predates page delivery sends one partition at a time and does not understand a
  deferral, so the client fails the partition instead and the kernel's failed-partition recovery
  delivers it again. Upgrade the Chronicle kernel to defer partitions.
  """

  defexception [:message, :partition]

  @impl true
  def exception(opts) do
    partition = Keyword.fetch!(opts, :partition)

    %__MODULE__{
      partition: partition,
      message:
        "Partition '#{partition}' cannot be deferred: the Chronicle kernel did not deliver a page, so it does not support deferrals. Upgrade the kernel to defer partitions."
    }
  end
end
