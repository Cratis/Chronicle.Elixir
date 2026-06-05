# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Events.InvalidMigrationGenerationGap do
  @moduledoc """
  Raised when a migration does not connect adjacent generations.
  """

  defexception [:message, :from_module, :to_module, :from_generation, :to_generation]

  @impl true
  def exception(opts) do
    from_module = Keyword.fetch!(opts, :from_module)
    to_module = Keyword.fetch!(opts, :to_module)
    from_generation = Keyword.fetch!(opts, :from_generation)
    to_generation = Keyword.fetch!(opts, :to_generation)

    %__MODULE__{
      from_module: from_module,
      to_module: to_module,
      from_generation: from_generation,
      to_generation: to_generation,
      message:
        "Migration from '#{inspect(from_module)}' (generation #{from_generation}) to " <>
          "'#{inspect(to_module)}' (generation #{to_generation}) is invalid. " <>
          "The upgrade generation must be exactly one more than the previous generation."
    }
  end
end
