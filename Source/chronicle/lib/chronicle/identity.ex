# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Identity do
  @moduledoc """
  Represents the identity that caused a state change.
  """

  @enforce_keys [:subject, :name]
  defstruct [:subject, :name, user_name: "", on_behalf_of: nil]

  @type t :: %__MODULE__{
          subject: String.t(),
          name: String.t(),
          user_name: String.t(),
          on_behalf_of: t() | nil
        }

  @system_subject "5d032c92-9d5e-41eb-947a-ee5314ed0032"
  @not_set_subject "1efc9b81-0612-4466-962c-86acc4e9a028"
  @unknown_subject "3321cf62-db16-425e-8173-99fcfefe11dd"

  @doc """
  Creates a new identity.
  """
  @spec new(String.t(), String.t(), String.t(), t() | nil) :: t()
  def new(subject, name, user_name \\ "", on_behalf_of \\ nil) do
    %__MODULE__{
      subject: subject,
      name: name,
      user_name: user_name,
      on_behalf_of: on_behalf_of
    }
  end

  @doc """
  Returns the default system identity.
  """
  @spec system() :: t()
  def system, do: new(@system_subject, "System", "system")

  @doc """
  Returns the sentinel identity for explicitly unset identity values.
  """
  @spec not_set() :: t()
  def not_set, do: new(@not_set_subject, "Not Set", "not-set")

  @doc """
  Returns the sentinel identity for unknown identity values.
  """
  @spec unknown() :: t()
  def unknown, do: new(@unknown_subject, "Unknown", "unknown")

  @doc """
  Removes duplicate subjects from an on-behalf-of identity chain.

  Keeps the first occurrence of each subject.
  """
  @spec without_duplicates(t()) :: t()
  def without_duplicates(%__MODULE__{} = identity) do
    {deduped, _seen} = dedupe(identity, MapSet.new())
    deduped
  end

  defp dedupe(%__MODULE__{} = identity, seen) do
    if MapSet.member?(seen, identity.subject) do
      {identity.on_behalf_of, seen}
    else
      seen = MapSet.put(seen, identity.subject)

      {on_behalf_of, seen} =
        case identity.on_behalf_of do
          %__MODULE__{} = nested -> dedupe(nested, seen)
          _ -> {nil, seen}
        end

      {%{identity | on_behalf_of: on_behalf_of}, seen}
    end
  end
end
