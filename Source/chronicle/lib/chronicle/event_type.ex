# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.EventType do
  @moduledoc """
  Macro for defining Chronicle event types.

  Use `Chronicle.EventType` in an event struct module to annotate it with a
  stable event type identifier and generation number. Chronicle uses these to
  register the event schema and route events to the correct observers.

  ## Usage

      defmodule MyApp.Events.AccountOpened do
        use Chronicle.EventType, id: "account-opened-v1"
        defstruct [:account_id, :owner_name, :initial_balance]
      end

  With an explicit generation:

      defmodule MyApp.Events.FundsDeposited do
        use Chronicle.EventType, id: "funds-deposited", generation: 2
        defstruct [:account_id, :amount, :currency]
      end

  ## Introspection

  Modules that `use Chronicle.EventType` expose metadata via
  `__chronicle_event_type__/1`:

      MyApp.Events.AccountOpened.__chronicle_event_type__(:id)
      #=> "account-opened-v1"

      MyApp.Events.AccountOpened.__chronicle_event_type__(:generation)
      #=> 1

  Chronicle also generates a `Jason.Encoder` implementation automatically so
  events can be serialized to JSON for storage. Event fields are encoded using
  their atom keys as-is (snake_case).
  """

  @doc """
  Returns metadata for this event type module.

  Accepts `:id` or `:generation` as the key.
  """
  @callback __chronicle_event_type__(key :: :id | :generation) :: term()

  defmacro __using__(opts) do
    event_type_id = Keyword.fetch!(opts, :id)
    generation = Keyword.get(opts, :generation, 1)

    quote do
      @behaviour Chronicle.EventType

      @chronicle_event_type_id unquote(event_type_id)
      @chronicle_event_type_generation unquote(generation)

      @impl Chronicle.EventType
      def __chronicle_event_type__(:id), do: @chronicle_event_type_id
      def __chronicle_event_type__(:generation), do: @chronicle_event_type_generation
    end
  end
end
