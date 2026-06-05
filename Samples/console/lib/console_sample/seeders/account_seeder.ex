# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule ConsoleSample.Seeders.AccountSeeder do
  @moduledoc """
  Seeds initial account data for the console sample application.

  This seeder demonstrates how to pre-populate the event store with baseline
  events during application startup.
  """

  use Chronicle.Seeder

  alias ConsoleSample.Events.{AccountOpened, FundsDeposited}

  @impl true
  def seed(builder) do
    builder
    |> Chronicle.Seeding.for(
      AccountOpened,
      "seed-account-1",
      [
        %AccountOpened{
          account_id: "seed-account-1",
          owner_name: "Alice Seed",
          initial_balance: 10_000
        }
      ]
    )
    |> Chronicle.Seeding.for(
      FundsDeposited,
      "seed-account-1",
      [
        %FundsDeposited{
          account_id: "seed-account-1",
          amount: 5_000
        }
      ]
    )
    |> Chronicle.Seeding.for(
      AccountOpened,
      "seed-account-2",
      [
        %AccountOpened{
          account_id: "seed-account-2",
          owner_name: "Bob Seed",
          initial_balance: 25_000
        }
      ]
    )
  end
end
