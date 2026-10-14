# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Discovery.Artifact do
  @moduledoc """
  One artifact found by `Chronicle.Discovery.Report.build/1`.

  Represents an artifact the client knows about, not a registration verdict or a kernel-side
  identity check — see `Chronicle.Discovery.DriftDetector` for that.
  """

  @enforce_keys [:kind, :module, :id]
  defstruct kind: nil, module: nil, id: nil, generation: nil, id_source: :unknown

  @type kind ::
          :event_type
          | :event_source
          | :reactor
          | :reducer
          | :projection
          | :read_model
          | :constraint
          | :webhook
          | :event_store_subscription
          | :seeder
          | :migration
          | :global_handler
          | :capture

  @typedoc """
  Whether an artifact's identifier was given explicitly, defaults to its declaring module's
  name (a rename hazard — see `Chronicle.Discovery.DefaultedIdWarning`), or isn't tracked for
  this kind of artifact (`:unknown`).
  """
  @type id_source :: :explicit | :module_name | :unknown

  @type t :: %__MODULE__{
          kind: kind(),
          module: module(),
          id: String.t(),
          generation: pos_integer() | nil,
          id_source: id_source()
        }
end
