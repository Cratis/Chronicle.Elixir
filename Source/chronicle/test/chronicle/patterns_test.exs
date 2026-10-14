# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.PatternsTest do
  use ExUnit.Case, async: true

  alias Chronicle.Patterns
  alias Chronicle.Patterns.FacetName

  describe "time_bucket/1" do
    test "04:59 is :night (just before early morning starts)" do
      assert Patterns.time_bucket(at(4, 59)) == :night
    end

    test "05:00 is :early_morning" do
      assert Patterns.time_bucket(at(5, 0)) == :early_morning
    end

    test "07:59 is :early_morning (just before morning starts)" do
      assert Patterns.time_bucket(at(7, 59)) == :early_morning
    end

    test "08:00 is :morning" do
      assert Patterns.time_bucket(at(8, 0)) == :morning
    end

    test "10:59 is :morning (just before midday starts)" do
      assert Patterns.time_bucket(at(10, 59)) == :morning
    end

    test "11:00 is :midday" do
      assert Patterns.time_bucket(at(11, 0)) == :midday
    end

    test "13:59 is :midday (just before afternoon starts)" do
      assert Patterns.time_bucket(at(13, 59)) == :midday
    end

    test "14:00 is :afternoon" do
      assert Patterns.time_bucket(at(14, 0)) == :afternoon
    end

    test "16:59 is :afternoon (just before evening starts)" do
      assert Patterns.time_bucket(at(16, 59)) == :afternoon
    end

    test "17:00 is :evening" do
      assert Patterns.time_bucket(at(17, 0)) == :evening
    end

    test "21:59 is :evening (just before night starts)" do
      assert Patterns.time_bucket(at(21, 59)) == :evening
    end

    test "22:00 is :night" do
      assert Patterns.time_bucket(at(22, 0)) == :night
    end

    test "uses the moment's own offset, not UTC" do
      # 09:00+02:00 is 07:00 UTC (:early_morning), but the moment's own hour is
      # 09, which is :morning — the rule must read the local hour.
      {:ok, moment} = DateTime.new(~D[2024-06-10], ~T[09:00:00], "Etc/UTC")
      moment = %{moment | utc_offset: 7200, std_offset: 0}

      assert Patterns.time_bucket(moment) == :morning
    end
  end

  describe "context_for_moment/2" do
    test "derives Day and TimeBucket from the moment" do
      # 2024-06-10 is a Monday.
      moment = at(9, 0)

      assert Patterns.context_for_moment(moment) == %{
               FacetName.day() => "Monday",
               FacetName.time_bucket() => "Morning"
             }
    end

    test "merges further facets passed as also_constraining" do
      moment = at(9, 0)

      context =
        Patterns.context_for_moment(moment, %{FacetName.aggregate_type() => "Invoice"})

      assert context == %{
               FacetName.aggregate_type() => "Invoice",
               FacetName.day() => "Monday",
               FacetName.time_bucket() => "Morning"
             }
    end

    test "the derived Day/TimeBucket win over a conflicting also_constraining value" do
      moment = at(9, 0)

      context =
        Patterns.context_for_moment(moment, %{
          FacetName.day() => "Someday",
          FacetName.time_bucket() => "Whenever"
        })

      assert context == %{
               FacetName.day() => "Monday",
               FacetName.time_bucket() => "Morning"
             }
    end

    test "every day of the week maps to its English name" do
      # 2024-06-10 is a Monday; walk the rest of that week.
      expected = ~w[Monday Tuesday Wednesday Thursday Friday Saturday Sunday]

      Enum.with_index(expected, fn name, offset ->
        moment = at(9, 0) |> DateTime.add(offset, :day)
        assert Patterns.context_for_moment(moment)[FacetName.day()] == name
      end)
    end
  end

  defp at(hour, minute) do
    {:ok, moment} = DateTime.new(~D[2024-06-10], Time.new!(hour, minute, 0), "Etc/UTC")
    moment
  end
end
