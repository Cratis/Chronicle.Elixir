# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule ConsoleSample.Migrations.AccountOpenedV2Migration do
  @moduledoc """
  Migrates the legacy `LegacyAccountOpened` event into the current
  `AccountOpened` generation.
  """

  use Chronicle.Events.Migration,
    from: {ConsoleSample.Events.LegacyAccountOpened, generation: 1},
    to: {ConsoleSample.Events.AccountOpened, generation: 2}

  alias Chronicle.Events.MigrationBuilder

  @impl true
  def upcast(builder) do
    builder
    |> MigrationBuilder.rename_property(:owner_name, :full_name)
    |> MigrationBuilder.default_value(:account_tier, "standard")
  end

  @impl true
  def downcast(builder) do
    builder
    |> MigrationBuilder.rename_property(:full_name, :owner_name)
  end
end
