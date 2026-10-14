# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Captures.MissingAppendCondition do
  @moduledoc """
  Raised at compile time when an `append/2` or `append/3` block does not declare `when:`.

  Every append must have exactly one `when` clause.
  """

  defexception [:message, :event_type]

  @impl true
  def exception(opts) do
    event_type = Keyword.fetch!(opts, :event_type)

    %__MODULE__{
      event_type: event_type,
      message:
        "The append block for event type '#{inspect(event_type)}' is missing a `when:` option."
    }
  end
end
