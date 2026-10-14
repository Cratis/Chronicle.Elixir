# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.ReadModels.DecisionReads do
  @moduledoc """
  Client-side decision-consistent reads: fold a read model, carry forward the exact log
  position it was folded at, and let `Chronicle.Transactions.UnitOfWork` guard a subsequent
  append with it — the Dynamic Consistency Boundary (DCB) pattern.

      Chronicle.decide(fn _unit_of_work ->
        {:ok, %{instance: seat}} = Chronicle.ReadModels.DecisionReads.get(MyApp.ReadModels.Seat, "seat-5")

        if seat == nil do
          Chronicle.EventSequences.EventLog.append("seat-5", %SeatBooked{by: "alice"})
        end
      end)

  If another process books the same seat between the read and the commit, the kernel rejects
  the whole batch and `Chronicle.decide/2` returns `{:error, %Chronicle.ReadModels.DecisionConflict{}}`
  instead of appending anything.

  Call `get/2` (or its stream variant, `get/4`) from inside a unit of work — it enrolls the read
  as a decision dependency automatically. Call `get_detached/2` (or `get_detached/4`) to fold the
  same way without an ambient unit of work, when you only need the guarded read's current value
  and are not about to commit anything against it.

  ## What can be guarded

  Not every read model shape can be protected: `admit/2` and `admit_for_stream/2` run the same
  checks `get/2`/`get_detached/2` do, without any I/O, so a caller can check eligibility ahead of
  time. See `Chronicle.ReadModels.DecisionReadRefused` for every refusal reason.

  ## Passive reducers (Elixir-only)

  The .NET and TypeScript clients refuse every reducer-backed read model outright. A read model
  produced by a **passive** reducer (`use Chronicle.Reducers.Reducer, active: false`) can be
  decision-read here instead: because a passive reducer is never kept warm by an observer, its
  current value is always folded fresh from `Chronicle.EventSequences.EventLog.get_for_event_source/2`,
  which makes it trivial to capture the exact boundary the fold stopped at. An **active**
  reducer is still refused with `:reducer` — only the client that asked for the fold knows it
  reached a consistent point, and an active reducer never asks.
  """

  alias Chronicle.Correlation.CorrelationId
  alias Chronicle.Events.ConcurrencyScope
  alias Chronicle.EventSequences.EventLog
  alias Chronicle.ReadModels
  alias Chronicle.ReadModels.{DecisionRead, DecisionReadRefused}
  alias Chronicle.Transactions.UnitOfWork

  @unavailable_sequence_number 18_446_744_073_709_551_615
  @max_attempts 3

  @type refusal_reason :: DecisionReadRefused.reason()

  @doc """
  Checks, without any I/O, whether `model_module` can back a model-keyed decision read.

  Returns `{:ok, event_types}` when admitted, or `{:error, reason}` — see
  `Chronicle.ReadModels.DecisionReadRefused` for every `reason`.
  """
  @spec admit(module(), keyword()) :: {:ok, [module()]} | {:error, refusal_reason()}
  def admit(model_module, opts \\ []), do: assess(model_module, opts)

  @doc """
  Checks, without any I/O, whether `model_module` can back a stream-scoped decision read.

  Elixir admits the same shapes for a stream-scoped read as for a model-keyed one; unlike the
  .NET client, it does not additionally admit a projection keyed by the event stream id itself.
  """
  @spec admit_for_stream(module(), keyword()) :: {:ok, [module()]} | {:error, refusal_reason()}
  def admit_for_stream(model_module, opts \\ []), do: assess(model_module, opts)

  @doc """
  Folds `model_module` at `key` in a fresh, guarded session, independently of any unit of work.

  Returns `{:ok, %Chronicle.ReadModels.DecisionRead{}}`, or `{:error, reason}` for a transport
  failure. Raises `Chronicle.ReadModels.DecisionReadRefused` when the model's shape cannot be
  guarded at all.

  ## Options

  Same as `Chronicle.ReadModels.get_instance_by_id/3`.
  """
  @spec get_detached(module(), String.t(), keyword()) ::
          {:ok, DecisionRead.t()} | {:error, term()}
  def get_detached(model_module, key, opts \\ []) when is_binary(key) do
    with {:ok, types} <- raise_on_refusal(admit(model_module, opts), model_module) do
      fold(model_module, key, key, types, nil, opts)
    end
  end

  @doc """
  Folds `model_module` guarding one event stream directly, independently of the model's own key.

  `event_source_id` is used both as the model's lookup key and as the target of the guard.
  Pass `:event_source_type` in `opts` to additionally narrow the event source type.

  Refused with `:all_streams_not_supported` when `event_stream_type` is empty or `"All"` — a
  stream-scoped guard needs a specific stream.
  """
  @spec get_detached(module(), String.t(), String.t(), String.t(), keyword()) ::
          {:ok, DecisionRead.t()} | {:error, term()}
  def get_detached(model_module, event_source_id, event_stream_type, event_stream_id, opts)
      when is_binary(event_source_id) and is_binary(event_stream_type) and
             is_binary(event_stream_id) do
    if event_stream_type in ["", "All"] do
      raise DecisionReadRefused, reason: :all_streams_not_supported, read_model: model_module
    else
      stream = %{
        event_source_id: event_source_id,
        event_stream_type: event_stream_type,
        event_stream_id: event_stream_id,
        event_source_type: Keyword.get(opts, :event_source_type, "")
      }

      with {:ok, types} <- raise_on_refusal(admit_for_stream(model_module, opts), model_module) do
        fold(model_module, event_source_id, event_source_id, types, stream, opts)
      end
    end
  end

  @doc """
  Folds `model_module` at `key` and enrolls the read as a decision dependency of the current
  unit of work, so `Chronicle.Transactions.UnitOfWork.commit/1` (and `Chronicle.decide/2`)
  guards the eventual append against anything else changing it first.

  Returns `{:error, :requires_unit_of_work}` when called outside `Chronicle.decide/2` or
  `Chronicle.Transactions.UnitOfWork.with_unit_of_work/2`. Raises
  `Chronicle.ReadModels.DecisionReadRefused` when the model's shape cannot be guarded.
  """
  @spec get(module(), String.t(), keyword()) ::
          {:ok, DecisionRead.t()} | {:error, :requires_unit_of_work | term()}
  def get(model_module, key, opts \\ []) when is_binary(key) do
    with_current_unit_of_work(fn ->
      with {:ok, read} <- get_detached(model_module, key, opts) do
        :ok = UnitOfWork.add_decision_read(UnitOfWork.current(), read)
        {:ok, read}
      end
    end)
  end

  @doc """
  Stream-scoped variant of `get/3`. See `get_detached/5` for the stream-scoping rules.
  """
  @spec get(module(), String.t(), String.t(), String.t(), keyword()) ::
          {:ok, DecisionRead.t()} | {:error, :requires_unit_of_work | term()}
  def get(model_module, event_source_id, event_stream_type, event_stream_id, opts \\ [])
      when is_binary(event_source_id) and is_binary(event_stream_type) and
             is_binary(event_stream_id) do
    with_current_unit_of_work(fn ->
      with {:ok, read} <-
             get_detached(model_module, event_source_id, event_stream_type, event_stream_id, opts) do
        :ok = UnitOfWork.add_decision_read(UnitOfWork.current(), read)
        {:ok, read}
      end
    end)
  end

  defp with_current_unit_of_work(fun) do
    if UnitOfWork.has_current?() do
      fun.()
    else
      {:error, :requires_unit_of_work}
    end
  end

  defp raise_on_refusal({:ok, types}, _model_module), do: {:ok, types}

  defp raise_on_refusal({:error, reason}, model_module),
    do: raise(DecisionReadRefused, reason: reason, read_model: model_module)

  # --- Admission -----------------------------------------------------------------------------

  defp assess(model_module, opts) do
    case reducer_for(model_module, opts) do
      nil ->
        assess_projection(model_module)

      reducer ->
        if reducer.__chronicle_reducer__(:active) do
          {:error, :reducer}
        else
          case reducer.__chronicle_reducer__(:handles) do
            [] -> {:error, :no_event_types}
            types -> {:ok, Enum.uniq(types)}
          end
        end
    end
  end

  defp assess_projection(model_module) do
    cond do
      not function_exported?(model_module, :__chronicle_read_model__, 1) ->
        {:error, :not_event_log}

      model_module.__chronicle_read_model__(:event_sequence) != "event-log" ->
        {:error, :not_event_log}

      model_module.__chronicle_read_model__(:join) != [] ->
        {:error, :join}

      model_module.__chronicle_read_model__(:removed_with_join) != [] ->
        {:error, :join}

      model_module.__chronicle_read_model__(:children) != [] ->
        {:error, :hierarchy}

      model_module.__chronicle_read_model__(:from_every) != [] ->
        {:error, :open_ended_event_types}

      not event_source_keyed?(model_module) ->
        {:error, :not_event_source_keyed}

      true ->
        case event_types(model_module) do
          [] -> {:error, :no_event_types}
          types -> admit_event_types(types)
        end
    end
  end

  defp admit_event_types(types) do
    if Enum.any?(types, &unsupported_event_type_id?/1) do
      {:error, :unsupported_event_type_id}
    else
      {:ok, types}
    end
  end

  defp event_source_keyed?(model_module) do
    (model_module.__chronicle_read_model__(:from) ++
       model_module.__chronicle_read_model__(:removed_with))
    |> Enum.all?(fn {_event, opts} -> default_key?(Keyword.get(opts, :key, :event_source_id)) end)
  end

  defp default_key?(:event_source_id), do: true
  defp default_key?("$eventSourceId"), do: true
  defp default_key?(_), do: false

  defp event_types(model_module) do
    (model_module.__chronicle_read_model__(:from) ++
       model_module.__chronicle_read_model__(:removed_with))
    |> Enum.map(fn {event_module, _opts} -> event_module end)
    |> Enum.uniq()
  end

  defp unsupported_event_type_id?(event_module) do
    function_exported?(event_module, :__chronicle_event_type__, 1) and
      String.contains?(event_module.__chronicle_event_type__(:id), ",")
  end

  defp reducer_for(model_module, opts) do
    client = Keyword.get(opts, :client, Chronicle.Client)

    case Chronicle.Client.config(client) do
      config when is_map(config) ->
        config
        |> Map.get(:reducers, [])
        |> Enum.find(fn reducer ->
          function_exported?(reducer, :__chronicle_reducer__, 1) and
            reducer.__chronicle_reducer__(:model) == model_module
        end)

      _ ->
        nil
    end
  end

  # --- Folding ---------------------------------------------------------------------------------

  defp fold(model_module, key, source_id, types, stream, opts) do
    case reducer_for(model_module, opts) do
      nil -> fold_projection(model_module, key, source_id, types, stream, opts, 0)
      reducer -> fold_passive_reducer(model_module, reducer, key, source_id, types, opts)
    end
  end

  defp fold_projection(model_module, key, source_id, types, stream, opts, attempt) do
    tail_opts = Keyword.take(opts, [:client, :namespace, :event_sequence_id])

    with {:ok, boundary_raw} <- EventLog.raw_tail_sequence_number(nil, tail_opts),
         {:ok, probe_raw} <-
           EventLog.raw_tail_sequence_number(source_id, probe_opts(tail_opts, types, stream)),
         {:ok, lookup} <- lookup_instance(model_module, key, stream, tail_opts) do
      evaluate_attempt(
        model_module,
        key,
        source_id,
        types,
        stream,
        opts,
        attempt,
        boundary_raw,
        probe_raw,
        lookup
      )
    end
  end

  defp lookup_instance(model_module, key, stream, tail_opts) do
    session_id = CorrelationId.create().value

    read_opts =
      tail_opts
      |> Keyword.put(:session_id, session_id)
      |> Keyword.merge(stream_lookup_opts(stream))

    result = ReadModels.get_instance_by_key_raw(model_module, key, read_opts)
    _ = ReadModels.dehydrate_session(model_module, key, session_id, tail_opts)
    result
  end

  defp stream_lookup_opts(nil), do: []

  defp stream_lookup_opts(%{} = stream) do
    [
      event_source_id: stream.event_source_id,
      event_source_type: stream.event_source_type,
      event_stream_type: stream.event_stream_type,
      event_stream_id: stream.event_stream_id
    ]
  end

  defp probe_opts(tail_opts, types, nil), do: Keyword.put(tail_opts, :event_types, types)

  defp probe_opts(tail_opts, types, %{} = stream) do
    tail_opts
    |> Keyword.put(:event_types, types)
    |> Keyword.put(:event_source_type, stream.event_source_type)
    |> Keyword.put(:event_stream_type, stream.event_stream_type)
    |> Keyword.put(:event_stream_id, stream.event_stream_id)
  end

  defp evaluate_attempt(
         model_module,
         key,
         source_id,
         types,
         stream,
         opts,
         attempt,
         boundary_raw,
         probe_raw,
         %{instance: instance, last_handled: last_raw, stream_scoped: stream_scoped?}
       ) do
    cond do
      stream != nil and not stream_scoped? ->
        raise DecisionReadRefused, reason: :stream_scope_not_supported, read_model: model_module

      actual?(probe_raw) and (not actual?(last_raw) or last_raw < probe_raw) ->
        retry_or_refuse(
          model_module,
          key,
          source_id,
          types,
          stream,
          opts,
          attempt,
          :fold_incomplete
        )

      actual?(last_raw) and (not actual?(boundary_raw) or last_raw > boundary_raw) ->
        retry_or_refuse(
          model_module,
          key,
          source_id,
          types,
          stream,
          opts,
          attempt,
          :fold_incomplete
        )

      true ->
        resolved_instance = if actual?(last_raw), do: instance, else: nil

        {:ok,
         build_decision_read(
           model_module,
           key,
           source_id,
           resolved_instance,
           boundary_raw,
           types,
           stream: stream,
           opts: opts
         )}
    end
  end

  defp retry_or_refuse(model_module, key, source_id, types, stream, opts, attempt, reason) do
    if attempt < @max_attempts - 1 do
      fold_projection(model_module, key, source_id, types, stream, opts, attempt + 1)
    else
      raise DecisionReadRefused, reason: reason, read_model: model_module
    end
  end

  defp actual?(@unavailable_sequence_number), do: false
  defp actual?(value) when is_integer(value) and value >= 0, do: true

  # Opt-in, Elixir-only: a passive reducer's read model is always folded fresh, so the boundary
  # is simply the tail captured right before the fold - there is no kernel-side session to
  # retry against, and so no retry loop either.
  defp fold_passive_reducer(model_module, reducer, key, source_id, types, opts) do
    tail_opts = Keyword.take(opts, [:client, :namespace, :event_sequence_id])

    with {:ok, boundary_raw} <- EventLog.raw_tail_sequence_number(nil, tail_opts),
         {:ok, events} <-
           EventLog.get_for_event_source(
             source_id,
             Keyword.merge(tail_opts, event_types: types, decode: true)
           ) do
      boundary = if actual?(boundary_raw), do: boundary_raw, else: 0

      # Events fetched after the boundary was captured could already include a concurrent
      # append; bound the fold to the boundary deterministically instead of racing the retry
      # dance a kernel-side session gets for free.
      instance =
        events
        |> Enum.filter(&(sequence_number(&1) <= boundary))
        |> Enum.reduce(nil, fn appended_event, model ->
          case appended_event.event do
            nil -> model
            event -> reducer.reduce(event, model, appended_event.context)
          end
        end)

      {:ok,
       build_decision_read(model_module, key, source_id, instance, boundary_raw, types,
         stream: nil,
         opts: opts
       )}
    end
  end

  defp sequence_number(%{context: %{sequence_number: seq}}), do: seq
  defp sequence_number(_), do: 0

  defp build_decision_read(model_module, key, source_id, instance, boundary_raw, types, extra) do
    stream = Keyword.get(extra, :stream)
    opts = Keyword.get(extra, :opts, [])
    client = Keyword.get(opts, :client, Chronicle.Client)
    config = Chronicle.Client.config(client)
    namespace = Keyword.get(opts, :namespace, Map.get(config, :namespace, ""))
    event_sequence_id = Keyword.get(opts, :event_sequence_id, "event-log")

    scope_opts =
      case stream do
        nil ->
          [event_source_id: true, event_types: types]

        %{} ->
          [
            event_source_id: true,
            event_source_type: stream.event_source_type,
            event_stream_type: stream.event_stream_type,
            event_stream_id: stream.event_stream_id,
            event_types: types
          ]
      end

    # An unavailable boundary means the whole event log was empty at read time - there is no real
    # sequence number low enough to say "reject anything newer than this" (0 is itself a real,
    # reachable position), so the guard instead asks the kernel to reject the commit if *any*
    # matching event exists at all, exactly like the optimistic strategy's first-append guard.
    scope =
      if actual?(boundary_raw) do
        ConcurrencyScope.new(boundary_raw, scope_opts)
      else
        ConcurrencyScope.expecting_no_matching_event(scope_opts)
      end

    %DecisionRead{
      read_model: model_module,
      key: key,
      instance: instance,
      event_source_id: source_id,
      event_store: Map.get(config, :event_store, ""),
      namespace: namespace,
      event_sequence_id: event_sequence_id,
      scope: scope,
      event_types: types,
      stream: stream
    }
  end
end
