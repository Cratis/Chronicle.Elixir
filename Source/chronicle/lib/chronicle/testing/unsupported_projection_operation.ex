# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Testing.UnsupportedProjectionOperation do
  @moduledoc """
  Raised by `Chronicle.Testing.Projections` when a read model declares a
  projection operation the in-memory evaluator does not support — `join/2`,
  `children/2`, `from_every/1` and their variants.

  These need the server-side projection engine; use
  `Chronicle.Testing.Integration.setup_isolated_client/2` against a real kernel
  instead of evaluating the projection in memory.
  """

  defexception [:message, :read_model, :operation]

  @impl true
  def exception(opts) do
    read_model = Keyword.fetch!(opts, :read_model)
    operation = Keyword.fetch!(opts, :operation)

    message =
      "#{inspect(read_model)} declares #{operation}, which Chronicle.Testing.Projections " <>
        "does not evaluate in memory. Use Chronicle.Testing.Integration.setup_isolated_client/2 " <>
        "against a real kernel instead."

    %__MODULE__{message: message, read_model: read_model, operation: operation}
  end
end
