# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.CausationType do
  @moduledoc """
  Identifies the kind of operation that caused an event append.
  """

  @enforce_keys [:value]
  defstruct [:value]

  @type t :: %__MODULE__{value: String.t()}

  @doc """
  Creates a new causation type wrapper.
  """
  @spec new(String.t()) :: t()
  def new(value) when is_binary(value), do: %__MODULE__{value: value}

  @doc """
  Root causation type.
  """
  @spec root() :: t()
  def root, do: new("Root")

  @doc """
  Unknown causation type.
  """
  @spec unknown() :: t()
  def unknown, do: new("Unknown")

  @doc """
  Causation type for single-event append operations.
  """
  @spec append_event() :: t()
  def append_event, do: new("ElixirClient.Append")

  @doc """
  Causation type for multi-event append operations.
  """
  @spec append_many_events() :: t()
  def append_many_events, do: new("ElixirClient.AppendMany")

  @doc """
  Causation type for transactional event sequence appends.
  """
  @spec transactional_event_sequence() :: t()
  def transactional_event_sequence, do: new("TransactionalEventSequence")
end
