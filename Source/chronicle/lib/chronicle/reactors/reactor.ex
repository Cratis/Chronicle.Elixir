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
      a different reactor and will reset its observation position. A defaulted id
      (pin it explicitly to silence this) emits a one-time warning when discovered —
      see `Chronicle.Discovery.DefaultedIdWarning`.
    * `:middleware` — modules implementing `Chronicle.Middleware` that wrap every `handle/2`
      call of this reactor (in addition to application-wide `config :cratis_chronicle, middleware:`)
    * `:once_only` — controls replay (mirrors .NET's `[OnceOnly]`). Reactors are replayable by
      default. `once_only: true` registers the reactor as not replayable
      (`IsNotReplayable: true`), so the kernel never replays it - use it for side effects such as
      sending an email. `once_only: [MyApp.Events.OrderShipped]` keeps the reactor replayable but
      skips the handlers of the listed events while replaying.
    * `:generation_delivery` — `:compatibility` (default) or `:pinned`. See
      "Pinned generation delivery" below.

  ## Pinned generation delivery

  By default (`:compatibility`), Chronicle upgrades every event to the handled module's own
  generation before delivery, so `handle/2` always sees that generation's shape regardless of
  which generation was actually appended. Set `generation_delivery: :pinned` to receive each
  event exactly as its own generation was appended instead - useful when a handler is written
  against an older generation and must see its original content rather than the upgraded one.
  `context.appended_generation` then tells you which generation was actually appended (`0`
  means unknown - an older kernel, or an event appended outside a registered event source).

  A client-wide default applies to every reactor that doesn't set `:generation_delivery`
  itself: pass `event_generation_delivery: :pinned` to `Chronicle.Client`. A reactor's own
  `:generation_delivery` option always wins over the client default.

  With `:pinned`, a reactor that handles two generations of the same event type id has no
  single generation to pin to and raises
  `Chronicle.Observers.MultipleGenerationsOfEventTypeInObserver` on start.

  ## Replay

  While the kernel replays a reactor, `context.replaying?` is `true`. Define the optional
  `handle_replay/2` callback to react differently during a replay (mirrors .NET's `[Replay]`):
  when it is defined it is called **instead of** `handle/2` for replayed events.

  > Replay exclusion is not exactly-once delivery. Recovering a failed partition can deliver an
  > event again as an ordinary observation; guard side effects with `context.delivery_id`.

  ## Registering with Chronicle.Client

      {Chronicle.Client,
        ...
        reactors: [MyApp.Reactors.NotificationReactor]}

  ## Event context

  The second argument to `handle/2` is a `Chronicle.Events.EventContext` struct (a map, so
  existing pattern matches on keys such as `:event_source_id` keep working). It carries the
  event type, event source and stream, sequence number, occurred time, event store, namespace,
  correlation id, `:caused_by` identity, causation chain, tags, hash and subject, plus a
  stable `:delivery_id` for building idempotency keys (the same value on every redelivery of
  the same event to this reactor).

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

  @doc """
  Optional. Handles an event while the reactor is being replayed, instead of `handle/2`.

  Same contract and return values as `handle/2`.
  """
  @callback handle_replay(event :: struct(), context :: map()) ::
              :ok | {:error, term()} | {:ok, struct() | [struct()]}

  @optional_callbacks handle_replay: 2,
                      on_replay_begin: 0,
                      on_replay_end: 0,
                      on_partition_replay_begin: 1,
                      on_partition_replay_end: 1

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @behaviour Chronicle.Reactors.Reactor

      Module.register_attribute(__MODULE__, :handles, accumulate: true)

      @chronicle_reactor_id Keyword.get(opts, :id, __MODULE__ |> to_string())
      @chronicle_reactor_id_source if Keyword.has_key?(opts, :id),
                                     do: :explicit,
                                     else: :module_name
      @chronicle_reactor_once_only Keyword.get(opts, :once_only, false)
      @chronicle_reactor_middleware Keyword.get(opts, :middleware, [])
      @chronicle_reactor_generation_delivery Keyword.get(opts, :generation_delivery)

      @before_compile Chronicle.Reactors.Reactor
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      @doc false
      def __chronicle_reactor__(:id), do: @chronicle_reactor_id
      def __chronicle_reactor__(:id_source), do: @chronicle_reactor_id_source
      def __chronicle_reactor__(:handles), do: @handles |> Enum.reverse()
      def __chronicle_reactor__(:once_only), do: @chronicle_reactor_once_only
      def __chronicle_reactor__(:middleware), do: @chronicle_reactor_middleware

      def __chronicle_reactor__(:generation_delivery),
        do: @chronicle_reactor_generation_delivery
    end
  end
end
