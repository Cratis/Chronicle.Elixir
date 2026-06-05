# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule ConsoleSample.Employees do
  @moduledoc """
  Shared employee data used by the seeder and interactive console.
  """

  alias ConsoleSample.Employees.Person

  @employees [
    %Person{id: "a0000001-0000-0000-0000-000000000000", first_name: "Ada", last_name: "Lovelace"},
    %Person{id: "a0000002-0000-0000-0000-000000000000", first_name: "Grace", last_name: "Hopper"},
    %Person{id: "a0000003-0000-0000-0000-000000000000", first_name: "Alan", last_name: "Turing"}
  ]

  @spec all() :: [Person.t()]
  def all, do: @employees

  @spec at(non_neg_integer()) :: Person.t() | nil
  def at(index), do: Enum.at(@employees, index)

  @spec email_for(Person.t()) :: String.t()
  def email_for(%Person{} = person) do
    "#{person.first_name}.#{person.last_name}@cratis.io"
    |> String.downcase()
  end
end
