# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

# Round trip against a real kernel for shared read-model subscriptions, observing collections, read
# model reactors, ad-hoc projection querying and projection waiting. Opt in like the other
# integration tests: point CHRONICLE_INTEGRATION_CONNECTION_STRING at a development kernel and run
# `mix test --include integration`.
defmodule Chronicle.Integration.ReadModelWatchersTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  alias Chronicle.EventSequences.EventLog
  alias Chronicle.Projections
  alias Chronicle.ReadModels

  defmodule AccountOpened do
    use Chronicle.Events.EventType, id: "RmwAccountOpened"
    defstruct balance: 0
  end

  defmodule BalanceChanged do
    use Chronicle.Events.EventType, id: "RmwBalanceChanged"
    defstruct amount: 0
  end

  defmodule AccountClosed do
    use Chronicle.Events.EventType, id: "RmwAccountClosed"
    defstruct []
  end

  defmodule Account do
    use Chronicle.ReadModels.ReadModel, id: "rmwAccount"

    defstruct id: "", balance: 0

    from(AccountOpened, set: [id: :event_source_id, balance: :balance])
    from(BalanceChanged, add: [balance: :amount])
    removed_with(AccountClosed, [])
  end

  defmodule NotifierReactor do
    use Chronicle.ReadModels.Reactor, model: Account, id: "rmwNotifier"

    @impl true
    def on_modified(account, _changeset), do: send(:rmw_it, {:modified, account})

    @impl true
    def on_removed(key, _changeset), do: send(:rmw_it, {:removed, key})
  end

  setup_all do
    prefix = System.get_env("CHRONICLE_INTEGRATION_EVENT_STORE_PREFIX", "rmw-elixir")

    {:ok, _} =
      Chronicle.Client.start_link(
        name: :rmw_it_client,
        connection_string: System.fetch_env!("CHRONICLE_INTEGRATION_CONNECTION_STRING"),
        event_store:
          "#{prefix}-#{System.system_time(:millisecond)}-#{System.unique_integer([:positive])}",
        discover: false,
        event_types: [AccountOpened, BalanceChanged, AccountClosed],
        read_models: [Account],
        read_model_reactors: [NotifierReactor]
      )

    :ok = Chronicle.Client.await_registration(:rmw_it_client, 60_000)
    :ok
  end

  setup do
    Process.register(self(), :rmw_it)
    on_exit(fn -> if Process.whereis(:rmw_it), do: Process.unregister(:rmw_it) end)
  end

  @opts [client: :rmw_it_client]

  # The shared watcher's first delivered item is a subscription-confirmation sentinel with an
  # empty model_key; skip it and wait for the real changeset.
  defp await_real_changeset(model) do
    receive do
      {:chronicle_read_model_changed, ^model, %{model_key: ""}} -> await_real_changeset(model)
      {:chronicle_read_model_changed, ^model, _changeset} = message -> message
    end
  end

  test "two subscribers of subscribe/2 each receive the changeset" do
    test = self()

    _second =
      spawn(fn ->
        {:ok, watcher} = ReadModels.subscribe(Account, @opts)
        send(test, {:subscribed, watcher})
        send(test, {:received_by_second, await_real_changeset(Account)})
      end)

    {:ok, watcher1} = ReadModels.subscribe(Account, @opts)
    assert_receive {:subscribed, watcher2}, 5_000
    assert watcher1 == watcher2

    id = "rmw-sub-#{System.unique_integer([:positive])}"
    {:ok, _} = EventLog.append_and_wait_for_completion(id, %AccountOpened{balance: 100}, @opts)

    assert {:chronicle_read_model_changed, Account, %{model_key: ^id}} =
             await_real_changeset(Account)

    assert_receive {:received_by_second,
                    {:chronicle_read_model_changed, Account, %{model_key: ^id}}},
                   15_000

    ReadModels.unsubscribe(watcher1)
  end

  test "observe/2 sends the initial list and then the updated one" do
    id = "rmw-obs-#{System.unique_integer([:positive])}"
    {:ok, _} = EventLog.append_and_wait_for_completion(id, %AccountOpened{balance: 10}, @opts)

    {:ok, observer} = ReadModels.observe(Account, @opts ++ [page_size: 500])

    assert_receive {:chronicle_read_model_instances, Account, result}, 15_000
    assert Enum.any?(result.instances, &(&1.id == id))

    {:ok, _} = EventLog.append_and_wait_for_completion(id, %BalanceChanged{amount: 5}, @opts)

    assert_receive {:chronicle_read_model_instances, Account, result2}, 15_000
    updated = Enum.find(result2.instances, &(&1.id == id))
    assert updated != nil
    assert updated.balance == 15

    ReadModels.unobserve(observer)
  end

  test "the read model reactor receives :modified and :removed" do
    id = "rmw-rx-#{System.unique_integer([:positive])}"
    {:ok, _} = EventLog.append_and_wait_for_completion(id, %AccountOpened{balance: 1}, @opts)
    {:ok, _} = EventLog.append_and_wait_for_completion(id, %BalanceChanged{amount: 9}, @opts)

    assert_receive {:modified, %Account{id: ^id, balance: 10}}, 15_000

    {:ok, _} = EventLog.append_and_wait_for_completion(id, %AccountClosed{}, @opts)

    assert_receive {:removed, ^id}, 15_000
  end

  test "query/2 returns results for a valid declaration and errors for an invalid one" do
    id = "rmw-pdl-#{System.unique_integer([:positive])}"
    {:ok, _} = EventLog.append_and_wait_for_completion(id, %AccountOpened{balance: 42}, @opts)

    assert {:ok, result} =
             Projections.query(
               """
               projection RmwAdhoc
                 from RmwAccountOpened
               """,
               @opts
             )

    assert Enum.any?(result.instances, &(&1["balance"] == 42))

    assert {:error, {:invalid_declaration, errors}} = Projections.query("not pdl at all", @opts)
    assert errors != []
  end

  test "wait_for/3 returns once the projection has caught up" do
    id = "rmw-wf-#{System.unique_integer([:positive])}"

    {:ok, %{sequence_number: sequence}} =
      EventLog.append_with_result(id, %AccountOpened{balance: 1}, @opts)

    assert :ok = Projections.wait_for(Account, sequence, Keyword.merge(@opts, timeout: 15_000))
  end
end
