# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Seeder do
  @moduledoc """
  Behaviour and macro for defining Chronicle seeders.

  Seeders pre-populate the event store with initial events during application
  startup. They are discovered and executed once when the Chronicle client
  initializes, allowing you to define baseline event data for development,
  testing, or initial production setup.

  ## Defining a seeder

  Use `Chronicle.Seeder` in a module and implement the `seed/1` callback.
  The callback receives a builder that accumulates events to be sent to
  Chronicle.

      defmodule MyApp.Seeders.AccountSeeder do
        use Chronicle.Seeder

        alias MyApp.Events.{AccountOpened, FundsDeposited}

        @impl true
        def seed(builder) do
          builder
          |> Chronicle.Seeding.for(
            AccountOpened,
            "account-1",
            [
              %AccountOpened{
                account_id: "account-1",
                owner_name: "Alice",
                initial_balance: 1000
              }
            ]
          )
          |> Chronicle.Seeding.for(
            FundsDeposited,
            "account-1",
            [
              %FundsDeposited{
                account_id: "account-1",
                amount: 500
              }
            ]
          )
        end
      end

  ## Options for `use Chronicle.Seeder`

    * `:id` — a stable string identifier for this seeder. Defaults to the
      module's full name. Changing this value does not affect seeding behavior,
      as seeders are executed once per startup, not tracked by the server.

  ## Registering with Chronicle.Client

      {Chronicle.Client,
        ...
        seeders: [MyApp.Seeders.AccountSeeder]}

  Or use auto-discovery (enabled by default):

      {Chronicle.Client,
        ...
        otp_app: :my_app}

  ## Seeding API

  The `seed/1` callback receives a `Chronicle.Seeding` builder struct with
  these functions:

    * `Chronicle.Seeding.for/3` — seed events of a specific type for an event source
    * `Chronicle.Seeding.for_event_source/2` — seed multiple event types for an event source
    * `Chronicle.Seeding.for_namespace/2` — scope subsequent events to a specific namespace

  ## When seeders run

  Seeders are discovered and executed during `Chronicle.Client` initialization.
  All seeders are invoked once, accumulating their events, then all events are
  sent to Chronicle in a single batch.

  Seeders should be idempotent. If your application restarts, seeders will run
  again. Chronicle's event log handles duplicates based on your event constraints.

  ## Return values

  `seed/1` must return the builder (possibly modified) or `:ok`. Errors are
  logged but do not prevent other seeders from running or the client from
  starting.
  """

  @doc """
  Populates the seeding builder with events.

  Called once per seeder during Chronicle client initialization. Receives a
  `Chronicle.Seeding` struct and should return the updated struct (or `:ok`).
  """
  @callback seed(builder :: Chronicle.Seeding.t()) :: Chronicle.Seeding.t() | :ok

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @behaviour Chronicle.Seeder

      @chronicle_seeder_id Keyword.get(opts, :id, __MODULE__ |> to_string())

      @before_compile Chronicle.Seeder
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      @doc false
      def __chronicle_seeder__(:id), do: @chronicle_seeder_id
    end
  end
end
