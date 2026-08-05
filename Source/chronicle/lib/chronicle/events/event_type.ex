# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Events.EventType do
  @moduledoc """
  Macro for defining Chronicle event types.

  Use `Chronicle.Events.EventType` in an event struct module to annotate it with a
  stable event type identifier and generation number. Chronicle uses these to
  register the event schema and route events to the correct observers.

  You can also declare model-bound constraints directly on the event type
  through attributes:

      defmodule MyApp.Events.UserRegistered do
        use Chronicle.Events.EventType, id: "user-registered-v1"
        defstruct [:email]

        @unique :email
        unique_event_type()
      end

      defmodule MyApp.Events.UserDeleted do
        use Chronicle.Events.EventType, id: "user-deleted-v1"
        defstruct [:email]

        @remove_constraint "email"
      end

  ## Usage

      defmodule MyApp.Events.AccountOpened do
        use Chronicle.Events.EventType, id: "account-opened-v1"
        defstruct [:account_id, :owner_name, :initial_balance]
      end

  With an explicit generation:

      defmodule MyApp.Events.FundsDeposited do
        use Chronicle.Events.EventType, id: "funds-deposited", generation: 2
        defstruct [:account_id, :amount, :currency]
      end

  ## Introspection

  Modules that `use Chronicle.Events.EventType` expose metadata via
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

  Accepts `:id`, `:generation`, or `:constraints` as the key.
  """
  @callback __chronicle_event_type__(key :: :id | :generation | :constraints | :pii) :: term()

  defmacro __using__(opts) do
    event_type_id = Keyword.fetch!(opts, :id)
    generation = Keyword.get(opts, :generation, 1)

    quote do
      @behaviour Chronicle.Events.EventType

      Module.register_attribute(__MODULE__, :unique, accumulate: true)
      Module.register_attribute(__MODULE__, :remove_constraint, accumulate: true)
      Module.register_attribute(__MODULE__, :unique_event_type, accumulate: true)
      Module.register_attribute(__MODULE__, :chronicle_pii, accumulate: true)

      import Chronicle.Events.EventType,
        only: [
          unique: 1,
          unique: 2,
          unique_event_type: 0,
          unique_event_type: 1,
          remove_constraint: 1
        ]

      import Chronicle.Compliance, only: [pii: 1, pii: 2]

      @chronicle_event_type_id unquote(event_type_id)
      @chronicle_event_type_generation unquote(generation)

      @before_compile Chronicle.Events.EventType
    end
  end

  @doc false
  # Generates the `__chronicle_event_type__/1` accessors after the module body
  # has been fully expanded. This is essential for the `:constraints` accessor:
  # the `@unique`, `@unique_event_type`, and `@remove_constraint` attributes are
  # accumulated by the `unique/1,2`, `unique_event_type/0,1`, and
  # `remove_constraint/1` macros that appear *after* `use Chronicle.Events.EventType`.
  # Reading them at `@before_compile` time captures their final values; reading
  # them inline in `__using__` would always see empty lists.
  defmacro __before_compile__(_env) do
    quote do
      @impl Chronicle.Events.EventType
      def __chronicle_event_type__(:id), do: @chronicle_event_type_id
      def __chronicle_event_type__(:generation), do: @chronicle_event_type_generation

      def __chronicle_event_type__(:constraints) do
        %{
          unique: Enum.reverse(@unique),
          unique_event_type: Enum.reverse(@unique_event_type),
          remove_constraint: Enum.reverse(@remove_constraint)
        }
      end

      def __chronicle_event_type__(:pii), do: Enum.reverse(@chronicle_pii)

      @doc false
      def __chronicle_pii__, do: Enum.reverse(@chronicle_pii)
    end
  end

  @doc """
  Declares a unique constraint for one or more event fields.

  This is equivalent to setting `@unique`. Supported `opts`:

    * `:name` — explicit constraint name (defaults to the first field name)
    * `:ignore_casing` — compare values case-insensitively
    * `:message` — human-readable message to use when the constraint is
      violated
  """
  defmacro unique(fields, opts \\ []) do
    quote do
      @unique {unquote(fields), unquote(opts)}
    end
  end

  @doc """
  Declares a unique constraint for the whole event type.

  This is equivalent to setting `@unique_event_type`. Supported `opts`:

    * `:name` — explicit constraint name (defaults to the event type id)
    * `:message` — human-readable message to use when the constraint is
      violated
  """
  defmacro unique_event_type(opts \\ []) do
    quote do
      @unique_event_type unquote(opts)
    end
  end

  @doc """
  Declares that appending this event removes a named constraint.

  This is equivalent to setting `@remove_constraint`.
  """
  defmacro remove_constraint(name) do
    quote do
      @remove_constraint unquote(name)
    end
  end
end
