# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Sinks.WellKnownSinkTypes do
  @moduledoc """
  Well-known sink type identifiers for Chronicle projections and reducers.

  Use these atoms as the `:default_sink_type_id` option when starting
  `Chronicle.Client`. The default is `:mongodb`.

  ## Available types

    * `:mongodb` — persists read models into MongoDB (default)
    * `:sql` — persists read models into a SQL database
    * `:in_memory` — persists read models in memory only
    * `:not_set` — no sink configured

  ## Example

      {Chronicle.Client,
        connection_string: "chronicle://localhost:35000?disableTls=true",
        event_store: "my-store",
        default_sink_type_id: :sql,
        read_models: [MyApp.ReadModels.Account]}
  """

  @mongodb "MongoDB"
  @sql "SQL"
  @in_memory "InMemory"
  @not_set "NotSet"

  @doc "Sink type identifier for MongoDB."
  @spec mongodb() :: String.t()
  def mongodb, do: @mongodb

  @doc "Sink type identifier for SQL."
  @spec sql() :: String.t()
  def sql, do: @sql

  @doc "Sink type identifier for InMemory."
  @spec in_memory() :: String.t()
  def in_memory, do: @in_memory

  @doc "Sink type identifier for NotSet (no sink)."
  @spec not_set() :: String.t()
  def not_set, do: @not_set

  @doc """
  Resolves an atom sink type name to its string identifier.

  Accepts `:mongodb`, `:sql`, `:in_memory`, or `:not_set`.
  Raises `ArgumentError` for unknown values.
  """
  @spec resolve(atom() | String.t()) :: String.t()
  def resolve(:mongodb), do: @mongodb
  def resolve(:sql), do: @sql
  def resolve(:in_memory), do: @in_memory
  def resolve(:not_set), do: @not_set
  def resolve(value) when is_binary(value), do: value

  def resolve(other) do
    raise ArgumentError,
          "Unknown sink type: #{inspect(other)}. " <>
            "Use :mongodb, :sql, :in_memory, or :not_set, or pass a string identifier directly."
  end
end
