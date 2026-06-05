# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.MigrationTest do
  use ExUnit.Case, async: true

  alias Chronicle.Events.{MigrationBuilder, Migrators}

  defmodule AccountOpenedV1 do
    use Chronicle.Events.EventType, id: "account-opened", generation: 1
    defstruct [:account_id, :owner_name, :initial_balance]
  end

  defmodule AccountOpened do
    use Chronicle.Events.EventType, id: "account-opened", generation: 2
    defstruct [:account_id, :full_name, :initial_balance, :account_tier]
  end

  defmodule AccountOpenedV2Migration do
    use Chronicle.Events.Migration,
      from: {AccountOpenedV1, generation: 1},
      to: {AccountOpened, generation: 2}

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

  describe "use Chronicle.Events.Migration" do
    test "exposes migration metadata" do
      assert AccountOpenedV2Migration.__chronicle_migration__(:from_module) == AccountOpenedV1
      assert AccountOpenedV2Migration.__chronicle_migration__(:to_module) == AccountOpened
      assert AccountOpenedV2Migration.__chronicle_migration__(:from_generation) == 1
      assert AccountOpenedV2Migration.__chronicle_migration__(:to_generation) == 2
      assert AccountOpenedV2Migration.__chronicle_migration__(:event_type_id) == "account-opened"
    end

    test "raises for non-adjacent generations" do
      assert_raise Chronicle.Events.InvalidMigrationGenerationGap, fn ->
        compile_invalid_migration(
          "GapMigration",
          1,
          3,
          "account-opened-gap",
          "account-opened-gap"
        )
      end
    end

    test "raises when event type ids differ" do
      assert_raise ArgumentError,
                   ~r/Migration from and to event types must have the same ID/,
                   fn ->
                     compile_invalid_migration(
                       "MismatchedIdsMigration",
                       1,
                       2,
                       "account-opened-a",
                       "account-opened-b"
                     )
                   end
    end
  end

  describe "Migrators" do
    test "groups migrations by event type id" do
      migrators = Migrators.new([AccountOpenedV2Migration])

      assert Migrators.all(migrators) == [AccountOpenedV2Migration]
      assert Migrators.for_event_type(migrators, AccountOpened) == [AccountOpenedV2Migration]
      assert Migrators.for_event_type(migrators, "account-opened") == [AccountOpenedV2Migration]
      assert Migrators.generations_for(migrators, AccountOpened) == [1, 2]
    end

    test "materializes migration definitions" do
      definition = Migrators.definition_for(AccountOpenedV2Migration)

      assert definition.from_generation == 1
      assert definition.to_generation == 2

      assert Jason.decode!(definition.upcast_jmes_path) == %{
               "fullName" => %{"$rename" => "ownerName"},
               "accountTier" => %{"$defaultValue" => "standard"}
             }

      assert Jason.decode!(definition.downcast_jmes_path) == %{
               "ownerName" => %{"$rename" => "fullName"}
             }
    end
  end

  describe "Chronicle.Artifacts" do
    test "discovers loaded migrations" do
      discovered = Chronicle.Artifacts.discover_loaded()
      assert AccountOpenedV2Migration in discovered.migrations
    end
  end

  defp compile_invalid_migration(name, from_generation, to_generation, from_id, to_id) do
    unique = System.unique_integer([:positive])

    Code.compile_string("""
    defmodule Chronicle.MigrationTest.#{name}#{unique}.FromEvent do
      use Chronicle.Events.EventType, id: #{inspect(from_id)}, generation: #{from_generation}
      defstruct []
    end

    defmodule Chronicle.MigrationTest.#{name}#{unique}.ToEvent do
      use Chronicle.Events.EventType, id: #{inspect(to_id)}, generation: #{to_generation}
      defstruct []
    end

    defmodule Chronicle.MigrationTest.#{name}#{unique} do
      use Chronicle.Events.Migration,
        from: {Chronicle.MigrationTest.#{name}#{unique}.FromEvent, generation: #{from_generation}},
        to: {Chronicle.MigrationTest.#{name}#{unique}.ToEvent, generation: #{to_generation}}

      def upcast(builder), do: builder
      def downcast(builder), do: builder
    end
    """)
  end
end
