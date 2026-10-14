# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Events.MigrationGenerationsMustShareEventTypeId do
  @moduledoc """
  Raised when the two generations referenced by a `Chronicle.Events.Migration` resolve to
  different event type ids.
  """

  defexception [:message, :from_module, :to_module, :from_id, :to_id]

  @impl true
  def exception(opts) do
    from_module = Keyword.fetch!(opts, :from_module)
    to_module = Keyword.fetch!(opts, :to_module)
    from_id = Keyword.fetch!(opts, :from_id)
    to_id = Keyword.fetch!(opts, :to_id)

    %__MODULE__{
      from_module: from_module,
      to_module: to_module,
      from_id: from_id,
      to_id: to_id,
      message:
        "Migration from '#{inspect(from_module)}' (event type '#{from_id}') to " <>
          "'#{inspect(to_module)}' (event type '#{to_id}') bridges two different event types. " <>
          "Both generations must resolve to the same event type id - mark the previous " <>
          "generation with generation_for: #{inspect(to_module)} instead of a separate :id."
    }
  end
end
