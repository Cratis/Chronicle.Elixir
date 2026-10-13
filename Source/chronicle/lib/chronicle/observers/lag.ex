# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Observers.Lag do
  @moduledoc """
  How far behind the tail of an event sequence each observer is.

  An evicted or stalled observer is invisible from the append side: appends keep succeeding
  while reactors, reducers and projections silently stop receiving events. The only reliable
  signal is the distance between the tail of the event sequence and the last event the observer
  handled - its *lag*.

  `measure/1` reads it once. `Chronicle.Observers.Lag.Reporter` polls it and publishes
  `:telemetry` events, which is how a dashboard or alert sees a stuck observer. Enable the
  reporter with the client option `observer_lag: [interval: 15_000]`.

  ## Telemetry

    * `[:chronicle, :observer, :lag]` - one event per observer per poll. Measurements:
      `%{lag: non_neg_integer(), tail: non_neg_integer(), last_handled: non_neg_integer()}`.
      Metadata: `%{observer_id: String.t(), type: atom(), running_state: atom(),
      event_sequence_id: String.t(), client: atom()}`.
  """

  alias Chronicle.EventSequences.EventLog
  alias Chronicle.Observers

  @type entry :: %{
          observer_id: String.t(),
          type: atom(),
          running_state: atom(),
          event_sequence_id: String.t(),
          last_handled: non_neg_integer(),
          tail: non_neg_integer(),
          lag: non_neg_integer()
        }

  @doc """
  Measures the lag of every observer of an event sequence.

  Options: `:client`, `:namespace`, `:event_sequence_id` (default `"event-log"`).
  """
  @spec measure(keyword()) :: {:ok, [entry()]} | {:error, term()}
  def measure(opts \\ []) do
    sequence = Keyword.get(opts, :event_sequence_id, "event-log")

    with {:ok, observers} <- Observers.get_all(opts),
         {:ok, tail} <- EventLog.get_tail_sequence_number(nil, opts) do
      {:ok,
       observers
       |> Enum.filter(&(&1.event_sequence_id == sequence))
       |> Enum.map(&entry(&1, tail))}
    end
  end

  @doc false
  def entry(observer, tail) do
    handled = observer.last_handled_event_sequence_number

    %{
      observer_id: observer.id,
      type: observer.type,
      running_state: observer.running_state,
      event_sequence_id: observer.event_sequence_id,
      last_handled: handled,
      tail: tail,
      lag: max(tail - handled, 0)
    }
  end

  defmodule Reporter do
    @moduledoc """
    Polls `Chronicle.Observers.Lag.measure/1` and publishes a telemetry event per observer.
    """
    use GenServer

    require Logger

    def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

    @impl true
    def init(opts) do
      interval = Keyword.get(opts, :interval, 15_000)

      state = %{
        client: Keyword.get(opts, :client, Chronicle.Client),
        interval: interval,
        opts: opts
      }

      Process.send_after(self(), :poll, interval)
      {:ok, state}
    end

    @impl true
    def handle_info(:poll, state) do
      measure_opts = Keyword.take(state.opts, [:client, :namespace, :event_sequence_id])

      case Chronicle.Observers.Lag.measure(measure_opts) do
        {:ok, entries} -> Enum.each(entries, &publish(&1, state.client))
        {:error, reason} -> Logger.debug("Observer lag poll skipped: #{inspect(reason)}")
      end

      Process.send_after(self(), :poll, state.interval)
      {:noreply, state}
    end

    def handle_info(_message, state), do: {:noreply, state}

    @doc false
    def publish(entry, client) do
      :telemetry.execute(
        [:chronicle, :observer, :lag],
        %{lag: entry.lag, tail: entry.tail, last_handled: entry.last_handled},
        %{
          observer_id: entry.observer_id,
          type: entry.type,
          running_state: entry.running_state,
          event_sequence_id: entry.event_sequence_id,
          client: client
        }
      )
    end
  end
end
