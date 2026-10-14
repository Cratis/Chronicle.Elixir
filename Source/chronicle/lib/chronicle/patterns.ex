# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Patterns do
  @moduledoc """
  Idiomatic Elixir interface for Chronicle behavior patterns.

  Behavior patterns are recurring combinations of facets — `Day`, `TimeBucket`,
  `CommandType`, `AggregateType` and so on — that Chronicle mined from the event
  history of an event store. They answer what usually happens, not what just
  happened.

  - `get_patterns/3` and `get_usual_actions/3` are the low-level facet-set
    queries: they match an arbitrary context against the mined patterns.
  - `get_patterns_at/3` is the ergonomic wrapper most applications want: "what
    does this scope usually do right now (or at some other moment)?" It derives
    `Day` and `TimeBucket` from the moment, using the moment's own offset — not
    UTC — so a scope's established morning behavior is asked about in their
    morning wherever they are.
  - `get_patterns_for_scope/2` and `get_scopes/1` inspect what has been mined.

  An empty result is an answer, not a failure: it says the scope has no
  established behavior for the asked context. Nothing is invented to fill the
  gap, so a caller can treat "no patterns" as "do not claim to know".

  ## Common options

  Every function accepts these options:

    * `:client` — the client name (default: `Chronicle.Client`)
    * `:namespace` — overrides the client's configured namespace
    * `:minimum_confidence` — the lowest confidence (`0.0`–`1.0`) an answer may
      hold. Defaults to the server's configured threshold.
    * `:max_results` — the largest number of answers to return. Defaults to the
      server's default.

  ## Examples

      {:ok, patterns} = Chronicle.Patterns.get_patterns_at("user-42")

      {:ok, patterns} =
        Chronicle.Patterns.get_patterns_at(
          "user-42",
          tomorrow_morning,
          also_constraining: %{Chronicle.Patterns.FacetName.aggregate_type() => "Invoice"}
        )
  """

  defmodule BehaviorPattern do
    @moduledoc """
    A recurring combination of facets that survived Chronicle's support and
    confidence thresholds.
    """

    @enforce_keys [
      :grouping_key,
      :facets,
      :occurrences,
      :confidence,
      :support,
      :weight,
      :first_seen,
      :last_seen
    ]
    defstruct grouping_key: nil,
              facets: %{},
              occurrences: 0,
              confidence: 0.0,
              support: 0.0,
              weight: 0.0,
              first_seen: nil,
              last_seen: nil

    @type t :: %__MODULE__{
            grouping_key: String.t(),
            facets: %{String.t() => String.t()},
            occurrences: non_neg_integer(),
            confidence: float(),
            support: float(),
            weight: float(),
            first_seen: DateTime.t() | String.t() | nil,
            last_seen: DateTime.t() | String.t() | nil
          }
  end

  defmodule FacetName do
    @moduledoc """
    Well-known facet name constants for `Chronicle.Patterns`.

    Use these as keys in a `get_patterns/3` or `get_usual_actions/3` context
    map, or in `get_patterns_at/3`'s `:also_constraining` option, instead of
    hand-typing the wire names.
    """

    @command_type "CommandType"
    @initiator_type "InitiatorType"
    @initiator_id "InitiatorId"
    @on_behalf_of "OnBehalfOf"
    @caused_by_command "CausedByCommand"
    @correlation_root_id "CorrelationRootId"
    @aggregate_type "AggregateType"
    @year "Year"
    @month "Month"
    @day "Day"
    @time_bucket "TimeBucket"

    @doc "The type of command — or, absent one, the event type — that produced the event."
    @spec command_type() :: String.t()
    def command_type, do: @command_type

    @doc "What kind of initiator caused the event — a user, an agent or the system itself."
    @spec initiator_type() :: String.t()
    def initiator_type, do: @initiator_type

    @doc "The identifier of the initiator that caused the event."
    @spec initiator_id() :: String.t()
    def initiator_id, do: @initiator_id

    @doc "The identity the initiator acted on behalf of, when it acted for someone else."
    @spec on_behalf_of() :: String.t()
    def on_behalf_of, do: @on_behalf_of

    @doc "The command one level up the causation chain from the one that produced the event."
    @spec caused_by_command() :: String.t()
    def caused_by_command, do: @caused_by_command

    @doc "The correlation the event belongs to, identifying the flow it took part in."
    @spec correlation_root_id() :: String.t()
    def correlation_root_id, do: @correlation_root_id

    @doc "The type of the event source the event was appended to."
    @spec aggregate_type() :: String.t()
    def aggregate_type, do: @aggregate_type

    @doc "The year the event occurred in."
    @spec year() :: String.t()
    def year, do: @year

    @doc "The month the event occurred in."
    @spec month() :: String.t()
    def month, do: @month

    @doc "The day of week the event occurred on."
    @spec day() :: String.t()
    def day, do: @day

    @doc "The `Chronicle.Patterns.time_bucket/1` the event occurred in."
    @spec time_bucket() :: String.t()
    def time_bucket, do: @time_bucket
  end

  alias Cratis.Chronicle.Contracts.Patterns.{
    AllPatternScopesRequest,
    MatchingPatternsRequest,
    Patterns,
    PatternsForScopeRequest,
    UsualActionsRequest
  }

  alias Chronicle.Connections.Connection
  alias Chronicle.WireResult

  @type time_bucket :: :early_morning | :morning | :midday | :afternoon | :evening | :night

  @day_names {"Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"}
  @time_bucket_names %{
    early_morning: "EarlyMorning",
    morning: "Morning",
    midday: "Midday",
    afternoon: "Afternoon",
    evening: "Evening",
    night: "Night"
  }

  @doc """
  Gets the patterns that apply to a context, most specific and most confident
  first.

  This is the low-level facet-set query. `get_patterns_at/3` is the ergonomic
  wrapper most applications want.

  `grouping_key` is the scope to ask within — typically a user. `context` is a
  map of facet name to facet value, which may constrain any subset of the
  facets (see `Chronicle.Patterns.FacetName`).

  Returns `{:ok, [%BehaviorPattern{}]}`, empty when nothing clears the
  confidence bar — that is itself the answer, not a failure.
  """
  @spec get_patterns(String.t(), %{String.t() => String.t()}, keyword()) ::
          {:ok, [BehaviorPattern.t()]} | {:error, term()}
  def get_patterns(grouping_key, context \\ %{}, opts \\ []) do
    with {:ok, channel, config} <- resolve_channel(opts) do
      request =
        struct(MatchingPatternsRequest,
          EventStore: config.event_store,
          Namespace: Keyword.get(opts, :namespace, config.namespace),
          GroupingKey: grouping_key,
          Context: context,
          MinimumConfidence: Keyword.get(opts, :minimum_confidence, 0.0),
          MaximumResults: Keyword.get(opts, :max_results, 0)
        )

      fetch_patterns(fn -> Patterns.Stub.matching_patterns(channel, request) end)
    end
  end

  @doc """
  Gets what usually happens in a context, most likely first, at most one
  answer per action.

  `grouping_key` is the scope to ask within — typically a user. `context` is a
  map of facet name to facet value describing the situation, which may
  constrain any subset of the facets (see `Chronicle.Patterns.FacetName`).

  Where `get_patterns/3` returns patterns that describe a situation, this
  returns the ones that say what is done in it. Read the action off a result
  with `pattern.facets[Chronicle.Patterns.FacetName.command_type()]`, and its
  likelihood from `confidence` — the chance of that action given the context
  it was established in.

  Returns `{:ok, [%BehaviorPattern{}]}`, empty when nothing clears the
  confidence bar — that is itself the answer, not a failure.
  """
  @spec get_usual_actions(String.t(), %{String.t() => String.t()}, keyword()) ::
          {:ok, [BehaviorPattern.t()]} | {:error, term()}
  def get_usual_actions(grouping_key, context \\ %{}, opts \\ []) do
    with {:ok, channel, config} <- resolve_channel(opts) do
      request =
        struct(UsualActionsRequest,
          EventStore: config.event_store,
          Namespace: Keyword.get(opts, :namespace, config.namespace),
          GroupingKey: grouping_key,
          Context: context,
          MinimumConfidence: Keyword.get(opts, :minimum_confidence, 0.0),
          MaximumResults: Keyword.get(opts, :max_results, 0)
        )

      fetch_patterns(fn -> Patterns.Stub.usual_actions(channel, request) end)
    end
  end

  @doc """
  Gets what a scope usually does at a moment, most likely first, at most one
  answer per action.

  The question an application actually has is "what does this scope usually do
  right now", and this is that question. `moment` defaults to now (`DateTime.now!("Etc/UTC")`) when not given; pass a `DateTime` carrying the moment's own
  offset for a scope not in UTC, so the derived bucket matches the one the
  event was actually mined in. `Day` and
  `TimeBucket` are derived from `moment` using its own offset — not UTC — with
  the same rule the engine mined with (see `time_bucket/1`), so the caller
  never writes that rule themselves and never passes those two facets.

  `:also_constraining` adds further facets (a map of facet name to facet
  value) to narrow the moment with more of the situation — the kind of thing
  being worked on, what caused the work. The derived `Day`/`TimeBucket` win on
  conflict with anything passed there, since the moment is what was asked
  about.

  Returns `{:ok, [%BehaviorPattern{}]}`, empty when nothing clears the
  confidence bar — that is itself the answer, not a failure.
  """
  @spec get_patterns_at(String.t(), DateTime.t() | nil, keyword()) ::
          {:ok, [BehaviorPattern.t()]} | {:error, term()}
  def get_patterns_at(grouping_key, moment \\ nil, opts \\ []) do
    context =
      context_for_moment(
        moment || DateTime.now!("Etc/UTC"),
        Keyword.get(opts, :also_constraining, %{})
      )

    get_usual_actions(grouping_key, context, opts)
  end

  @doc """
  Builds the facet-set context `get_patterns_at/3` asks with for a given
  moment: `also_constraining` with `Day` and `TimeBucket` derived from
  `moment` put on top, so the derived values win on conflict.

  Exposed as its own pure function because it is the part of `get_patterns_at/3`
  that actually matters (see the module docs) and is otherwise untestable
  without a live kernel.
  """
  @spec context_for_moment(DateTime.t(), %{String.t() => String.t()}) :: %{
          String.t() => String.t()
        }
  def context_for_moment(%DateTime{} = moment, also_constraining \\ %{}) do
    also_constraining
    |> Map.put(FacetName.day(), day_name(moment))
    |> Map.put(FacetName.time_bucket(), time_bucket_name(time_bucket(moment)))
  end

  @doc """
  Gets every pattern established for a scope.
  """
  @spec get_patterns_for_scope(String.t(), keyword()) ::
          {:ok, [BehaviorPattern.t()]} | {:error, term()}
  def get_patterns_for_scope(grouping_key, opts \\ []) do
    with {:ok, channel, config} <- resolve_channel(opts) do
      request =
        struct(PatternsForScopeRequest,
          EventStore: config.event_store,
          Namespace: Keyword.get(opts, :namespace, config.namespace),
          GroupingKey: grouping_key
        )

      fetch_patterns(fn -> Patterns.Stub.patterns_for_scope(channel, request) end)
    end
  end

  @doc """
  Gets the scopes that have established patterns.
  """
  @spec get_scopes(keyword()) :: {:ok, [String.t()]} | {:error, term()}
  def get_scopes(opts \\ []) do
    with {:ok, channel, config} <- resolve_channel(opts) do
      request =
        struct(AllPatternScopesRequest,
          EventStore: config.event_store,
          Namespace: Keyword.get(opts, :namespace, config.namespace)
        )

      resilient_result =
        with {:ok, envelope} <- Patterns.Stub.all_pattern_scopes(channel, request) do
          WireResult.unwrap(envelope)
        end

      case resilient_result do
        {:ok, scopes} -> {:ok, Enum.map(scopes || [], &Map.get(&1, :Id))}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc """
  Gets the part of the day (`:early_morning`, `:morning`, `:midday`,
  `:afternoon`, `:evening`, or `:night`) a moment falls in, using the same
  rule Chronicle's kernel bucketed events with when it mined patterns.

  Read from the offset `moment` carries, not from UTC: somebody who works at
  nine in the morning does so at nine in their own morning, and normalizing to
  UTC first would scatter that one behavior across buckets as they travel or
  as daylight saving shifts.

  | Hours | Bucket |
  | --- | --- |
  | 05:00–08:00 | `:early_morning` |
  | 08:00–11:00 | `:morning` |
  | 11:00–14:00 | `:midday` |
  | 14:00–17:00 | `:afternoon` |
  | 17:00–22:00 | `:evening` |
  | 22:00–05:00 | `:night` |
  """
  @spec time_bucket(DateTime.t()) :: time_bucket()
  def time_bucket(%DateTime{} = moment) do
    case moment.hour do
      hour when hour >= 5 and hour < 8 -> :early_morning
      hour when hour >= 8 and hour < 11 -> :morning
      hour when hour >= 11 and hour < 14 -> :midday
      hour when hour >= 14 and hour < 17 -> :afternoon
      hour when hour >= 17 and hour < 22 -> :evening
      _hour -> :night
    end
  end

  defp time_bucket_name(bucket), do: Map.fetch!(@time_bucket_names, bucket)

  # Elixir's Calendar.ISO day_of_week is 1 (Monday) through 7 (Sunday), matching
  # @day_names's order, and the moment's own offset is already reflected in its
  # `:hour`/day-of-week fields because DateTime never normalizes to UTC.
  defp day_name(%DateTime{} = moment) do
    elem(@day_names, Date.day_of_week(moment) - 1)
  end

  defp fetch_patterns(call) do
    resilient_result =
      with {:ok, envelope} <- call.() do
        WireResult.unwrap(envelope)
      end

    case resilient_result do
      {:ok, patterns} -> {:ok, Enum.map(patterns || [], &decode_pattern/1)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp decode_pattern(pattern) do
    %BehaviorPattern{
      grouping_key: Map.get(pattern, :GroupingKey),
      facets: Map.get(pattern, :Facets, %{}),
      occurrences: Map.get(pattern, :Occurrences, 0),
      confidence: Map.get(pattern, :Confidence, 0.0),
      support: Map.get(pattern, :Support, 0.0),
      weight: Map.get(pattern, :Weight, 0.0),
      first_seen: decode_timestamp(Map.get(pattern, :FirstSeen)),
      last_seen: decode_timestamp(Map.get(pattern, :LastSeen))
    }
  end

  defp decode_timestamp(nil), do: nil

  defp decode_timestamp(%{Value: value}) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, timestamp, _offset} -> timestamp
      _ -> value
    end
  end

  defp decode_timestamp(value), do: value

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
