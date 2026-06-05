# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Reactors.Reactor do
  @moduledoc """
  Behaviour and macro for defining Chronicle reactors.

  Reactors observe events and react to them with side effects — sending emails,
  calling external APIs, updating caches, etc. They run in Chronicle's
  observation pipeline and receive events as they are appended.

  ## Defining a reactor

  Use `Chronicle.Reactors.Reactor` in a module and implement the `handle/2` callback.
  Declare which event types the reactor handles using the `@handles` module
  attribute.

      defmodule MyApp.Reactors.NotificationReactor do
        use Chronicle.Reactors.Reactor

        @handles MyApp.Events.AccountOpened
        @handles MyApp.Events.FundsDeposited

        @impl true
        def handle(%MyApp.Events.AccountOpened{} = event, _context) do
          # Send welcome email
          MyApp.Mailer.send_welcome(event.owner_name)
          :ok
        end

        def handle(%MyApp.Events.FundsDeposited{} = event, _context) do
          # Notify account holder
          :ok
        end
      end

  ## Options for `use Chronicle.Reactors.Reactor`

    * `:id` — a stable string identifier for this reactor. Defaults to the
      module's full name. Changing this value causes Chronicle to treat this as
      a different reactor and will reset its observation position.

  ## Registering with Chronicle.Client

      {Chronicle.Client,
        ...
        reactors: [MyApp.Reactors.NotificationReactor]}

  ## Event context

  The second argument to `handle/2` is a map with the following keys:

    * `:event_source_id` — the event source (e.g. aggregate ID)
    * `:sequence_number` — the event's position in the event log
    * `:occurred` — when the event was appended (ISO 8601 string)
    * `:event_store` — the event store name
    * `:namespace` — the namespace
    * `:correlation_id` — the correlation ID for the append operation

  ## Return values

  `handle/2` must return `:ok` on success, or `{:error, reason}` on failure.
  Failures are reported back to Chronicle as a failed partition, which can be
  retried or replayed.
  """

  @doc """
  Handles an event dispatched by Chronicle.

  Called once per event for each partition. Must return `:ok` or `{:error, reason}`.
  """
  @callback handle(event :: struct(), context :: map()) :: :ok | {:error, term()}

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @behaviour Chronicle.Reactors.Reactor

      Module.register_attribute(__MODULE__, :handles, accumulate: true)

      @chronicle_reactor_id Keyword.get(opts, :id, __MODULE__ |> to_string())

      @before_compile Chronicle.Reactors.Reactor
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      @doc false
      def __chronicle_reactor__(:id), do: @chronicle_reactor_id
      def __chronicle_reactor__(:handles), do: @handles |> Enum.reverse()
    end
  end
end
