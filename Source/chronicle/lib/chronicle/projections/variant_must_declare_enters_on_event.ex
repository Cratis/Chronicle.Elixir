# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Projections.VariantMustDeclareEntersOnEvent do
  @moduledoc """
  Raised when a read model or declarative projection variant does not declare at least one
  `enters_on` event.
  """

  defexception [:message, :variant_module]

  @impl true
  def exception(opts) do
    variant_module = Keyword.fetch!(opts, :variant_module)

    %__MODULE__{
      variant_module: variant_module,
      message:
        "Read model variant '#{inspect(variant_module)}' does not declare an enters_on event. " <>
          "A variant must name at least one event that may create or resurrect it."
    }
  end
end
