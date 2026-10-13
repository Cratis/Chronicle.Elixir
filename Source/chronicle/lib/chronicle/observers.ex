# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Observers do
  @moduledoc """
  Idiomatic API for working with Chronicle observers.

  An observer is a reactor, reducer, or projection registered against an event sequence to be
  told about the events it cares about. This module is how an application finds out what the
  event store knows about its observers, and how it removes one whose declaring code is gone.

  Mirrors the C#, Kotlin, and TypeScript clients' `IObservers`.

  ## Options

    * `:client` — the client name (default: `Chronicle.Client`)
    * `:namespace` — accepted for consistency with other APIs and ignored here
  """

  alias Chronicle.Connections.Connection

  alias Cratis.Chronicle.Contracts.Observation.{
    AllObserversRequest,
    FastForward,
    Observers,
    RemoveObserver
  }

  @event_log_id "event-log"

  defmodule ObserverInformation do
    @moduledoc """
    What the event store knows about one of its observers.
    """

    @enforce_keys [:id, :event_sequence_id, :type, :running_state]
    defstruct id: nil,
              event_sequence_id: nil,
              type: :unknown,
              running_state: :unknown,
              last_handled_event_sequence_number: 0,
              next_event_sequence_number: 0,
              handled_event_count: 0

    @type observer_type :: :unknown | :reactor | :projection | :reducer | :external
    @type running_state ::
            :unknown | :active | :suspended | :replaying | :disconnected | :quarantined

    @type t :: %__MODULE__{
            id: String.t(),
            event_sequence_id: String.t(),
            type: observer_type(),
            running_state: running_state(),
            last_handled_event_sequence_number: non_neg_integer(),
            next_event_sequence_number: non_neg_integer(),
            handled_event_count: non_neg_integer()
          }
  end

  defmodule RemovalResult do
    @moduledoc """
    What came back from asking an event store to remove an observer.
    """

    @enforce_keys [:outcome, :blocking_namespace]
    defstruct outcome: nil, blocking_namespace: ""

    @type outcome ::
            :removed | :observer_not_found | :observer_active | :observer_subscribed

    @type t :: %__MODULE__{outcome: outcome(), blocking_namespace: String.t()}

    @doc """
    Whether the observer was actually removed.
    """
    @spec removed?(t()) :: boolean()
    def removed?(%__MODULE__{outcome: :removed}), do: true
    def removed?(%__MODULE__{}), do: false
  end

  defmodule FastForwardResult do
    @moduledoc """
    What came back from asking an event store to fast forward an observer.
    """

    @enforce_keys [:outcome]
    defstruct outcome: nil,
              previous_next_event_sequence_number: 0,
              next_event_sequence_number: 0

    @type outcome :: :fast_forwarded | :already_at_tail | :replaying | :not_available

    @type t :: %__MODULE__{
            outcome: outcome(),
            previous_next_event_sequence_number: non_neg_integer(),
            next_event_sequence_number: non_neg_integer()
          }
  end

  @doc """
  Gets every observer registered in the event store's current namespace.
  """
  @spec get_all(keyword()) :: {:ok, [ObserverInformation.t()]} | {:error, term()}
  def get_all(opts \\ []) do
    with {:ok, channel, config} <- resolve_channel(opts) do
      namespace = Keyword.get(opts, :namespace, config.namespace)

      request =
        struct(AllObserversRequest, EventStore: config.event_store, Namespace: namespace)

      case Observers.Stub.get_observers(channel, request) do
        {:ok, response} ->
          observers =
            response
            |> Map.get(:items, [])
            |> Enum.map(&decode_observer_information/1)

          {:ok, observers}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Removes an observer and everything keyed to it.

  For the observer whose declaring code is gone — a read model and its projection that were
  deleted, a reactor that was removed. The observer it registered stays behind, settles into
  `:disconnected`, and keeps its records in the event store forever.

  Removal covers the whole event store, because an observer's definition is a store-level
  record. It refuses while the observer is running or has a subscribed client in any
  namespace, so what it can remove is only ever an observer no client is reporting — stop the
  declaring application first if you mean to remove a live one. Read model data and sink
  containers are left untouched.
  """
  @spec remove(String.t(), keyword()) :: {:ok, RemovalResult.t()} | {:error, term()}
  def remove(observer_id, opts \\ []) when is_binary(observer_id) do
    with {:ok, channel, config} <- resolve_channel(opts) do
      namespace = Keyword.get(opts, :namespace, config.namespace)
      event_sequence_id = Keyword.get(opts, :event_sequence_id, @event_log_id)

      request =
        struct(RemoveObserver,
          EventStore: config.event_store,
          Namespace: namespace,
          ObserverId: observer_id,
          EventSequenceId: event_sequence_id
        )

      case Observers.Stub.remove_observer(channel, request) do
        {:ok, response} ->
          {:ok, decode_removal_result(response)}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Fast forwards an observer to the tail of its event sequence.

  Every event the observer has not yet handled is skipped without invoking it, and its failed
  partitions are discarded. State it has already built is kept, so the effect of the skipped
  events is missing from it; replay the observer instead to rebuild.

  Returns a `FastForwardResult` saying what happened and where the observer is now. An observer
  that is replaying is left alone and reported as `:replaying`.
  """
  @spec fast_forward(String.t(), keyword()) :: {:ok, FastForwardResult.t()} | {:error, term()}
  def fast_forward(observer_id, opts \\ []) when is_binary(observer_id) do
    with {:ok, channel, config} <- resolve_channel(opts) do
      namespace = Keyword.get(opts, :namespace, config.namespace)
      event_sequence_id = Keyword.get(opts, :event_sequence_id, @event_log_id)

      request =
        struct(FastForward,
          EventStore: config.event_store,
          Namespace: namespace,
          ObserverId: observer_id,
          EventSequenceId: event_sequence_id
        )

      case Observers.Stub.fast_forward(channel, request) do
        {:ok, response} ->
          {:ok, decode_fast_forward_result(response)}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc false
  def decode_fast_forward_result(response) do
    %FastForwardResult{
      outcome: decode_fast_forward_outcome(Map.get(response, :Outcome)),
      previous_next_event_sequence_number: Map.get(response, :PreviousNextEventSequenceNumber, 0),
      next_event_sequence_number: Map.get(response, :NextEventSequenceNumber, 0)
    }
  end

  @doc false
  def decode_observer_information(observer) do
    %ObserverInformation{
      id: Map.get(observer, :Id, ""),
      event_sequence_id: Map.get(observer, :EventSequenceId, ""),
      type: decode_observer_type(Map.get(observer, :Type)),
      running_state: decode_running_state(Map.get(observer, :RunningState)),
      last_handled_event_sequence_number: Map.get(observer, :LastHandledEventSequenceNumber, 0),
      next_event_sequence_number: Map.get(observer, :NextEventSequenceNumber, 0),
      handled_event_count: Map.get(observer, :HandledEventCount, 0)
    }
  end

  @doc false
  def decode_removal_result(response) do
    %RemovalResult{
      outcome: decode_removal_outcome(Map.get(response, :Outcome)),
      blocking_namespace: Map.get(response, :BlockingNamespace, "")
    }
  end

  defp decode_observer_type(:Reactor), do: :reactor
  defp decode_observer_type(:Projection), do: :projection
  defp decode_observer_type(:Reducer), do: :reducer
  defp decode_observer_type(:External), do: :external
  defp decode_observer_type(_), do: :unknown

  # The wire enum names this OBSERVER_RUNNING_STATE_Disconnected — protoc prefixes the literal
  # to dodge a collision elsewhere in the file — so a clause matching the plain atom would
  # never fire and every disconnected observer would silently decode as :unknown.
  defp decode_running_state(:Active), do: :active
  defp decode_running_state(:Suspended), do: :suspended
  defp decode_running_state(:Replaying), do: :replaying
  defp decode_running_state(:OBSERVER_RUNNING_STATE_Disconnected), do: :disconnected
  defp decode_running_state(:Quarantined), do: :quarantined
  defp decode_running_state(_), do: :unknown

  defp decode_fast_forward_outcome(:FastForwarded), do: :fast_forwarded
  defp decode_fast_forward_outcome(:AlreadyAtTail), do: :already_at_tail
  defp decode_fast_forward_outcome(:Replaying), do: :replaying
  defp decode_fast_forward_outcome(_), do: :not_available

  defp decode_removal_outcome(:Removed), do: :removed
  defp decode_removal_outcome(:ObserverNotFound), do: :observer_not_found
  defp decode_removal_outcome(:ObserverActive), do: :observer_active
  defp decode_removal_outcome(:ObserverSubscribed), do: :observer_subscribed

  defp resolve_channel(opts) do
    client = Keyword.get(opts, :client, Chronicle.Client)

    case Chronicle.Client.config(client) do
      config when is_map(config) ->
        case Connection.channel(config.connection) do
          {:ok, channel} -> {:ok, channel, config}
          error -> error
        end

      _ ->
        {:error, :no_client}
    end
  end
end
