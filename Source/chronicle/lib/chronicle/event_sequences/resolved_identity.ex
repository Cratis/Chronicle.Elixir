# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.EventSequences.ResolvedIdentity do
  @moduledoc """
  The identity that caused an event, as the kernel resolved it when reading event metadata
  (`Chronicle.EventSequences.Streams.get_metadata/2` and `get_metadata_at/2`).

  Unlike `Chronicle.Identity` (what an append declared), this also carries how the kernel
  resolved it at read time - `:resolution` - mirroring the .NET client's `IdentityResolution`:

    * `:resolved` — the identity was resolved successfully
    * `:name_unavailable` — the subject was resolved, but a display name was not
    * `:missing` — no identity was recorded
    * `:not_set` — the identity was explicitly unset
    * `:system` — the system identity caused the event
  """

  @enforce_keys [:subject, :name]
  defstruct [:subject, :name, user_name: "", resolution: :not_set, on_behalf_of: nil]

  @type resolution :: :resolved | :name_unavailable | :missing | :not_set | :system

  @type t :: %__MODULE__{
          subject: String.t(),
          name: String.t(),
          user_name: String.t(),
          resolution: resolution(),
          on_behalf_of: t() | nil
        }
end
