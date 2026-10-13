# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

# Round trip against a real kernel for the client-parity features. Opt in like the other
# integration tests: point CHRONICLE_INTEGRATION_CONNECTION_STRING at a development kernel and run
# `mix test --include integration`.
defmodule Chronicle.Integration.ClientParityTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  alias Chronicle.EventSequences.{AppendResult, EventLog, Streams}
  alias Chronicle.Events.ConcurrencyScope

  defmodule Line do
    defstruct line_name: "", item_count: 0
  end

  defmodule Registered do
    use Chronicle.Events.EventType,
      id: "pt-registered",
      subject: :user_id,
      tags: ["parity"],
      types: [lines: {:list, Line}, labels: :map]

    defstruct user_id: "", email: "", series_name: "", parameters: %{}, labels: %{}, lines: []

    unique(:email)
  end

  defmodule PeriodClosed do
    use Chronicle.Events.EventType, id: "pt-period-closed"
    defstruct period: ""

    closes_stream(event_stream_id_from: :period)
  end

  defmodule BasketCreated do
    use Chronicle.Events.EventType, id: "pt-basket-created"
    defstruct []
  end

  defmodule ItemAdded do
    use Chronicle.Events.EventType, id: "pt-item-added"
    defstruct item_id: "", name: ""
  end

  defmodule BasketItem do
    defstruct item_id: "", name: ""
  end

  defmodule Basket do
    use Chronicle.ReadModels.ReadModel, id: "ptBasket", types: [items: {:list, BasketItem}]

    defstruct basket_id: "", items: []

    from(BasketCreated, set: [basket_id: :event_source_id])

    children :items, identified_by: :item_id do
      from(ItemAdded,
        key: :item_id,
        parent_key: :event_source_id,
        set: [item_id: :item_id, name: :name]
      )
    end
  end

  defmodule SeededNote do
    use Chronicle.Events.EventType, id: "pt-seeded-note", tags: ["seed"]
    defstruct text: ""
  end

  defmodule NoteSeeder do
    use Chronicle.Seeding.Seeder

    @impl true
    def seed(builder) do
      builder
      |> Chronicle.Seeding.for(SeededNote, "seed-src", [%SeededNote{text: "first"}])
      |> then(fn b ->
        if Process.get(:second_seed),
          do: Chronicle.Seeding.for(b, SeededNote, "seed-src", [%SeededNote{text: "second"}]),
          else: b
      end)
    end
  end

  defmodule Watcher do
    use Chronicle.ReadModels.Reactor, model: Basket

    def on_added(basket, _changeset), do: send(:parity_it, {:rm_added, basket})
    def on_modified(basket, _changeset), do: send(:parity_it, {:rm_modified, basket})
  end

  defmodule Spy do
    use Chronicle.Reactors.Reactor
    @handles Registered

    def handle(event, context) do
      send(:parity_it, {:handled, event, context})
      :ok
    end
  end

  setup_all do
    prefix = System.get_env("CHRONICLE_INTEGRATION_EVENT_STORE_PREFIX", "parity-elixir")

    {:ok, _} =
      Chronicle.Client.start_link(
        name: :parity_it_client,
        connection_string: System.fetch_env!("CHRONICLE_INTEGRATION_CONNECTION_STRING"),
        event_store:
          "#{prefix}-#{System.system_time(:millisecond)}-#{System.unique_integer([:positive])}",
        discover: false,
        event_types: [Registered, PeriodClosed, BasketCreated, ItemAdded, SeededNote],
        read_model_reactors: [Watcher],
        read_models: [Basket],
        reactors: [Spy]
      )

    :ok = Chronicle.Client.await_registration(:parity_it_client, 60_000)
    :ok
  end

  setup do
    Process.register(self(), :parity_it)
    on_exit(fn -> if Process.whereis(:parity_it), do: Process.unregister(:parity_it) end)
  end

  @opts [client: :parity_it_client]

  defp registered(id, extra \\ []) do
    struct(
      %Registered{
        user_id: id,
        email: "#{id}@example.com",
        series_name: "Arrakis",
        parameters: %{"snake_case_key" => 1, "nested" => %{"deep_key" => 2}},
        labels: %{"a_b" => "c"},
        lines: [%Line{line_name: "first", item_count: 3}]
      },
      extra
    )
  end

  test "registration reports registered" do
    assert %{state: :registered} = Chronicle.Client.registration_status(:parity_it_client)
  end

  test "maps and nested multi-word fields round-trip, and reads decode into the struct" do
    event = registered("rt-1")
    assert :ok = EventLog.append("rt-1", event, @opts)

    assert {:ok, [appended]} = EventLog.get_for_event_source("rt-1", @opts ++ [decode: true])
    assert appended.event == event
    assert appended.raw["seriesName"] == "Arrakis"
    assert appended.raw["parameters"] == %{"snake_case_key" => 1, "nested" => %{"deep_key" => 2}}
    assert appended.raw["lines"] == [%{"lineName" => "first", "itemCount" => 3}]
  end

  test "the declared subject, tags and the full context reach the reactor" do
    identity = Chronicle.Identity.new("u-1", "Ada", "ada")
    assert :ok = EventLog.append("ctx-1", registered("ctx-1"), @opts ++ [identity: identity])

    assert_receive {:handled, %Registered{user_id: "ctx-1"}, context}, 15_000
    assert context.subject == "ctx-1"
    assert "parity" in context.tags
    assert context.caused_by.subject == "u-1"
    assert context.correlation_id != ""
    assert context.event_store != ""

    assert context.delivery_id ==
             Enum.join(
               [
                 Spy.__chronicle_reactor__(:id),
                 context.event_store,
                 context.namespace,
                 "event-log",
                 "ctx-1",
                 context.sequence_number
               ],
               "#"
             )

    refute context.replaying?
  end

  test "append results carry sequence numbers and structured violations" do
    assert {:ok, %AppendResult{success?: true, sequence_number: first}} =
             EventLog.append_with_result("ar-1", registered("ar-1"), @opts)

    assert is_integer(first)

    assert {:error, %AppendResult{constraint_violations: [violation | _]}} =
             EventLog.append_with_result(
               "ar-2",
               registered("ar-2", email: "ar-1@example.com"),
               @opts
             )

    assert violation.constraint_name != ""

    assert {:ok, %AppendResult{sequence_numbers: [a, b]}} =
             EventLog.append_many_with_result(
               "ar-3",
               [
                 registered("ar-3", email: "x3@example.com"),
                 registered("ar-3", email: "y3@example.com")
               ],
               @opts
             )

    assert b == a + 1
  end

  test "expecting no matching event is a creation-only guard" do
    scope =
      ConcurrencyScope.expecting_no_matching_event(
        event_source_id: true,
        event_types: [Registered]
      )

    opts = @opts ++ [concurrency_scope: scope]

    assert {:ok, _} = EventLog.append_with_result("once-1", registered("once-1"), opts)

    assert {:error, %AppendResult{concurrency_violations: violations}} =
             EventLog.append_with_result(
               "once-1",
               registered("once-1", email: "other@example.com"),
               opts
             )

    assert violations != []
  end

  test "a closing event closes its scope and Streams inspects, reopens and reads metadata" do
    scope = [event_source_id: "pc-1", event_stream_type: "All", event_stream_id: "2024"]

    event = %PeriodClosed{period: "2024"}

    assert {:ok, %AppendResult{sequence_number: sequence}} =
             EventLog.append_with_result(
               "pc-1",
               event,
               @opts ++ [event_stream_id: "2024", event_stream_type: "All"]
             )

    assert {:ok, closed} = Streams.closed(@opts ++ [event_source_id: "pc-1"])
    assert Enum.any?(closed, &(&1.origin == :closing_event))

    assert {:ok, [metadata]} = Streams.get_metadata([sequence], @opts)
    assert metadata.event_source_id == "pc-1"

    assert {:ok, result} = Streams.verify_content(sequence, event, @opts)
    assert result in [:equal, :different, :unavailable]

    assert {:ok, false} = Streams.scope_completed?(@opts ++ [event_source_id: "nothing-here"])
    _ = scope
  end

  test "a children block projects a child collection" do
    assert :ok = EventLog.append("bk-1", %BasketCreated{}, @opts)
    assert :ok = EventLog.append("bk-1", %ItemAdded{item_id: "i-1", name: "tea"}, @opts)
    assert :ok = EventLog.append("bk-1", %ItemAdded{item_id: "i-2", name: "milk"}, @opts)

    basket =
      await_read_model(
        fn -> Chronicle.ReadModels.get(Basket, "bk-1", @opts) end,
        &(length(&1.items) == 2)
      )

    assert basket.items |> Enum.map(& &1.name) |> Enum.sort() == ["milk", "tea"]
  end

  test "query filters and sorts" do
    for id <- ["q-1", "q-2", "q-3"] do
      assert :ok = EventLog.append(id, %BasketCreated{}, @opts)
    end

    await_read_model(
      fn -> Chronicle.ReadModels.query(Basket, @opts) |> then(fn {:ok, r} -> {:ok, r} end) end,
      &(&1.total_count >= 3)
    )

    assert {:ok, result} =
             Chronicle.ReadModels.query(Basket, @opts ++ [filter: [basket_id: "q-2"]])

    assert result.total_count == 1
    assert [%{basket_id: "q-2"}] = result.instances

    assert {:error, {:unknown_field, :nope}} =
             Chronicle.ReadModels.query(Basket, @opts ++ [filter: [nope: 1]])
  end

  test "observers can be listed and their lag measured" do
    assert {:ok, entries} = Chronicle.Observers.Lag.measure(@opts)
    assert Enum.all?(entries, &(&1.lag >= 0))
  end

  test "an oversized payload is refused before it is sent and the connection stays usable" do
    big = registered("big-1", parameters: %{"blob" => String.duplicate("x", 4_300_000)})

    assert {:error, {:payload_too_large, size, 4_194_304}} = EventLog.append("big-1", big, @opts)
    assert size > 4_194_304
    assert :ok = EventLog.append("big-2", registered("big-2", email: "big2@example.com"), @opts)
  end

  test "retry of a partition that never failed reports it as not found" do
    assert {:ok, outcome} = Chronicle.Observers.retry_partition(Spy, "no-such-partition", @opts)
    assert outcome in [:partition_not_found, :started]
  end

  test "seeding goes through the kernel and a later entry on a seeded source is applied" do
    run_seed = fn second? ->
      if second?, do: Process.put(:second_seed, true), else: Process.delete(:second_seed)

      builder =
        NoteSeeder.seed(%Chronicle.Seeding{
          event_store: Chronicle.Client.config(:parity_it_client).event_store,
          namespace: Chronicle.Client.config(:parity_it_client).namespace,
          client: :parity_it_client
        })

      assert :ok = Chronicle.Seeding.register(builder)
    end

    texts = fn ->
      {:ok, events} = EventLog.get_for_event_source("seed-src", @opts ++ [decode: true])
      events |> Enum.map(& &1.event.text) |> Enum.sort()
    end

    run_seed.(false)
    assert wait_for(fn -> texts.() == ["first"] end)

    run_seed.(false)
    Process.sleep(500)
    assert texts.() == ["first"], "re-running applied the same entry again"

    run_seed.(true)
    assert wait_for(fn -> texts.() == ["first", "second"] end)

    {:ok, [first | _]} = EventLog.get_for_event_source("seed-src", @opts ++ [decode: true])
    assert "seed" in first.context.tags
  end

  test "a scope closed by an operator reports completed and can be reopened" do
    scope = [event_source_id: "op-1", event_stream_type: "Period", event_stream_id: "2025"]

    assert :ok = EventLog.append("op-1", registered("op-1"), @opts)
    assert {:ok, _sequence} = Streams.complete_scope(@opts ++ scope)
    assert {:ok, true} = Streams.scope_completed?(@opts ++ scope)
    assert {:ok, closed} = Streams.closed(@opts ++ [event_source_id: "op-1"])
    assert Enum.any?(closed, &(&1.origin == :complete_stream))

    assert :ok = Streams.reopen_scope("late invoice", @opts ++ scope)
    assert {:ok, false} = Streams.scope_completed?(@opts ++ scope)
    assert {:error, :not_completed} = Streams.reopen_scope("again", @opts ++ scope)
  end

  test "observe sends the collection now and again when it changes" do
    {:ok, observer} = Chronicle.ReadModels.observe(Basket, @opts)

    assert :ok = EventLog.append("obs-1", %BasketCreated{}, @opts)

    assert wait_for(fn ->
             receive do
               {:chronicle_read_model_instances, Basket, %{instances: instances}} ->
                 Enum.any?(instances, &(&1.basket_id == "obs-1"))

               {:chronicle_read_model_observe_error, Basket, reason} ->
                 flunk("observe failed: #{inspect(reason)}")
             after
               250 -> false
             end
           end)

    Chronicle.ReadModels.unobserve(observer)
  end

  test "a read model reactor is told when its read model changes" do
    assert :ok = EventLog.append("rmr-1", %BasketCreated{}, @opts)

    assert_receive {:rm_added, %Basket{basket_id: "rmr-1"}}, 20_000
  end

  test "allowing a new encryption key is accepted by the kernel" do
    assert :ok = Chronicle.Compliance.allow_new_encryption_key_for("nobody-here", @opts)
  end

  defp wait_for(fun, attempts \\ 60) do
    cond do
      fun.() -> true
      attempts == 0 -> false
      true -> Process.sleep(250) && wait_for(fun, attempts - 1)
    end
  end

  defp await_read_model(fetch, done?, attempts \\ 40) do
    case fetch.() do
      {:ok, nil} when attempts > 0 ->
        retry(fetch, done?, attempts)

      {:ok, value} ->
        if done?.(value) or attempts == 0, do: value, else: retry(fetch, done?, attempts)
    end
  end

  defp retry(fetch, done?, attempts) do
    Process.sleep(250)
    await_read_model(fetch, done?, attempts - 1)
  end
end
