# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.MigrationBuilderTest do
  use ExUnit.Case, async: true

  alias Chronicle.Events.MigrationBuilder

  describe "MigrationBuilder" do
    test "builds rename and default value expressions using camelCase property names" do
      builder =
        MigrationBuilder.new()
        |> MigrationBuilder.rename_property(:owner_name, :full_name)
        |> MigrationBuilder.default_value(:account_tier, "standard")

      assert MigrationBuilder.to_map(builder) == %{
               "fullName" => %{"$rename" => "ownerName"},
               "accountTier" => %{"$defaultValue" => "standard"}
             }
    end

    test "builds split and combine expressions" do
      builder =
        MigrationBuilder.new()
        |> MigrationBuilder.split_property(:full_name, :first_name, " ", 0)
        |> MigrationBuilder.combine_properties([:first_name, :last_name], :full_name, " ")

      assert MigrationBuilder.to_map(builder) == %{
               "firstName" => %{
                 "$split" => %{"source" => "fullName", "separator" => " ", "part" => 0}
               },
               "fullName" => %{
                 "$combine" => %{
                   "sources" => ["firstName", "lastName"],
                   "separator" => " "
                 }
               }
             }
    end

    test "keeps single-argument copy operations as a no-op" do
      builder = MigrationBuilder.new() |> MigrationBuilder.copy_property(:owner_name)
      assert MigrationBuilder.to_map(builder) == %{}
    end

    test "copies between differently named properties" do
      builder = MigrationBuilder.new() |> MigrationBuilder.copy_property(:owner_name, :full_name)
      assert MigrationBuilder.to_map(builder) == %{"fullName" => %{"$rename" => "ownerName"}}
    end
  end
end
