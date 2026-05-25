# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.CorrelationIdManager do
  @moduledoc """
  Process-scoped correlation id manager.

  This provides an idiomatic Elixir alternative to AsyncLocalStorage-based
  context in other clients by using the process dictionary.
  """

  alias Chronicle.CorrelationId

  @process_key {__MODULE__, :current}

  @doc """
  Gets the current correlation id for the calling process.

  If no correlation id has been set, a new one is generated and returned.
  """
  @spec current() :: CorrelationId.t()
  def current do
    case Process.get(@process_key) do
      %CorrelationId{} = correlation_id -> correlation_id
      _ -> CorrelationId.create()
    end
  end

  @doc """
  Sets the current correlation id for the calling process.

  Accepts either a `%Chronicle.CorrelationId{}` or a raw string id.
  """
  @spec set_current(CorrelationId.t() | String.t()) :: CorrelationId.t()
  def set_current(%CorrelationId{} = correlation_id) do
    Process.put(@process_key, correlation_id)
    correlation_id
  end

  def set_current(value) when is_binary(value), do: set_current(CorrelationId.new(value))

  @doc """
  Clears the current correlation id and replaces it with a new generated id.
  """
  @spec clear() :: CorrelationId.t()
  def clear do
    correlation_id = CorrelationId.create()
    Process.put(@process_key, correlation_id)
    correlation_id
  end
end
