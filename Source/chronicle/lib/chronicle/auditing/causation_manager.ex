# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Auditing.CausationManager do
  @moduledoc """
  Process-scoped causation chain manager.

  Maintains a root causation entry and any additional entries added in the
  current process.
  """

  alias Chronicle.Auditing.{CausationEntry, CausationType}

  @root_key {__MODULE__, :root}
  @chain_key {__MODULE__, :chain}

  @doc """
  Gets the current causation chain for the calling process.
  """
  @spec get_current_chain() :: [CausationEntry.t()]
  def get_current_chain do
    root = Process.get(@root_key, default_root())
    chain = Process.get(@chain_key, [])
    [root | chain]
  end

  @doc """
  Defines the root causation entry for the calling process.
  """
  @spec define_root(map()) :: CausationEntry.t()
  def define_root(properties \\ %{}) do
    root = CausationEntry.new(CausationType.root(), properties)
    Process.put(@root_key, root)
    root
  end

  @doc """
  Adds a causation entry to the current process chain.
  """
  @spec add(CausationType.t() | String.t(), map()) :: CausationEntry.t()
  def add(type, properties \\ %{}) do
    entry = CausationEntry.new(type, properties)
    Process.put(@chain_key, Process.get(@chain_key, []) ++ [entry])
    entry
  end

  @doc """
  Clears the current process causation root and chain.
  """
  @spec clear() :: :ok
  def clear do
    Process.delete(@root_key)
    Process.delete(@chain_key)
    :ok
  end

  defp default_root, do: CausationEntry.new(CausationType.root(), %{})
end
