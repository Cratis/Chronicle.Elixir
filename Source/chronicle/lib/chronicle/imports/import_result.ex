# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Imports.ImportResult do
  @moduledoc """
  The result of an import.

  `state` is where the import ended up: `:completed` when every event was committed (or
  already appended), `:failed` when validation rejected it, `:abandoned` when it was
  abandoned. An import that was completed without waiting for its commit can also report
  `:validating` or `:committing`.

  With `on_invalid: :reject` (the default) a single rejected event fails the whole import
  and nothing is committed; `rejections` then names every rejected event by its index in
  the import. `rejected_count` counts rejections beyond those the kernel keeps in the list.
  """

  alias Chronicle.Imports.ImportRejection

  @type state ::
          :open | :staging | :validating | :committing | :completed | :failed | :abandoned

  defstruct import_id: "",
            state: :open,
            events_staged: 0,
            events_committed: 0,
            already_appended: 0,
            first_sequence_number: nil,
            last_sequence_number: nil,
            rejected_count: 0,
            rejections: [],
            failure_reason: nil

  @type t :: %__MODULE__{
          import_id: String.t(),
          state: state(),
          events_staged: non_neg_integer(),
          events_committed: non_neg_integer(),
          already_appended: non_neg_integer(),
          first_sequence_number: non_neg_integer() | nil,
          last_sequence_number: non_neg_integer() | nil,
          rejected_count: non_neg_integer(),
          rejections: [ImportRejection.t()],
          failure_reason: String.t() | nil
        }

  @doc "Returns true when the import completed."
  @spec success?(t()) :: boolean()
  def success?(%__MODULE__{state: state}), do: state == :completed

  @doc "Returns true when the import reached a state it will not leave."
  @spec terminal?(t()) :: boolean()
  def terminal?(%__MODULE__{state: state}), do: state in [:completed, :failed, :abandoned]
end
