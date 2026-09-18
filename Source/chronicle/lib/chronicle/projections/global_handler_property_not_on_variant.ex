# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Projections.GlobalHandlerPropertyNotOnVariant do
  @moduledoc """
  Raised when a `Chronicle.Projections.GlobalHandler` shared handler declares a mapping that
  targets a member a variant it applies to does not have.
  """

  defexception [:message, :handler_module, :variant_module, :property]

  @impl true
  def exception(opts) do
    handler_module = Keyword.fetch!(opts, :handler_module)
    variant_module = Keyword.fetch!(opts, :variant_module)
    property = Keyword.fetch!(opts, :property)

    %__MODULE__{
      handler_module: handler_module,
      variant_module: variant_module,
      property: property,
      message:
        "Shared handler '#{inspect(handler_module)}' maps to property '#{property}', which " <>
          "does not exist on variant '#{inspect(variant_module)}'."
    }
  end
end
