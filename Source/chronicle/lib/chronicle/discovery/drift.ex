# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Discovery.Drift do
  @moduledoc """
  One artifact identity finding from `Chronicle.Discovery.DriftDetector`: evidence that the
  kernel's record of an artifact and the client's current code have diverged, not proof of a
  problem on its own.
  """

  @enforce_keys [:kind, :id, :reason, :severity]
  defstruct kind: nil, id: nil, reason: nil, severity: nil

  @type kind :: :event_type | :reactor | :reducer | :projection

  @type reason ::
          :schema_changed_without_generation
          | :observer_missing_from_code
          | :observer_event_types_changed

  @typedoc """
  `:warning` blocks registration under `drift_policy: :fail`. `:info` (a reducer or
  projection finding) never blocks registration under any policy, but is still logged under
  `:warn` and `:fail`.
  """
  @type severity :: :info | :warning

  @type t :: %__MODULE__{kind: kind(), id: String.t(), reason: reason(), severity: severity()}
end
