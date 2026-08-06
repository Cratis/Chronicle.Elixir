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

  `handle/2` must return one of:

    * `:ok` — success, no side effect.
    * `{:error, reason}` — failure. Reported back to Chronicle as a failed
      partition, which can be retried or replayed.
    * `{:ok, event_or_events}` — success, with one or more events to append as
      a side effect. `event_or_events` may be:
      * a single event struct — appended to the triggering event source id.
      * a list of event structs — appended atomically (single append-many) to
        the triggering event source id.
      * a `Chronicle.EventSequences.EventForEventSourceId` struct — appended to
        its own explicit event source id.
      * a list of `EventForEventSourceId` structs (optionally mixed with bare
        event structs, which are then targeted at the triggering event source
        id) — appended atomically across all their (possibly different) event
        source ids.

  If appending a side effect fails, `handle/2`'s overall result becomes
  `{:error, reason}` — reported the same way as a plain `{:error, reason}` return.

  ## Replay lifecycle (optional)

  Implement any of `on_replay_begin/0`, `on_replay_end/0`,
  `on_partition_replay_begin/1`, `on_partition_replay_end/1` to be notified when
  Chronicle starts or finishes replaying this reactor — either as a whole, or
  for a single partition (event source). All four are optional; implement only
  the ones you need.

      @impl true
      def on_replay_begin, do: Logger.info("Replay starting")

      @impl true
      def on_replay_end, do: Logger.info("Replay finished")

  These are notifications, not events to handle — they run outside the normal
  `handle/2` dispatch, are not subject to failed-partition tracking, and a
  raised exception is logged and swallowed rather than reported to Chronicle.
  """

  @doc """
  Handles an event dispatched by Chronicle.

  Called once per event for each partition. Must return `:ok`, `{:error, reason}`,
  or `{:ok, event_or_events}` to append a side effect (see moduledoc).
  """
  @callback handle(event :: struct(), context :: map()) ::
              :ok | {:error, term()} | {:ok, struct() | [struct()]}

  @doc "Called when a full replay of this reactor begins."
  @callback on_replay_begin() :: any()

  @doc "Called when a full replay of this reactor ends."
  @callback on_replay_end() :: any()

  @doc "Called when replay of a single partition (event source) begins."
  @callback on_partition_replay_begin(partition :: String.t()) :: any()

  @doc "Called when replay of a single partition (event source) ends."
  @callback on_partition_replay_end(partition :: String.t()) :: any()

  @optional_callbacks on_replay_begin: 0,
                       on_replay_end: 0,
                       on_partition_replay_begin: 1,
                       on_partition_replay_end: 1

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
