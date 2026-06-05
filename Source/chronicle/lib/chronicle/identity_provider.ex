# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.IdentityProvider do
  @moduledoc """
  Process-scoped identity provider.

  Stores the current identity in the process dictionary so identity flows
  naturally through the calling process.
  """

  alias Chronicle.Identity

  @process_key {__MODULE__, :current}

  @doc """
  Gets the current identity for the calling process.
  """
  @spec get_current() :: Identity.t()
  def get_current do
    case Process.get(@process_key) do
      %Identity{} = identity -> identity
      _ -> Identity.system()
    end
  end

  @doc """
  Sets the current identity for the calling process.
  """
  @spec set_current_identity(Identity.t()) :: Identity.t()
  def set_current_identity(%Identity{} = identity) do
    Process.put(@process_key, identity)
    identity
  end

  @doc """
  Clears the current identity for the calling process.
  """
  @spec clear_current_identity() :: :ok
  def clear_current_identity do
    Process.delete(@process_key)
    :ok
  end
end
