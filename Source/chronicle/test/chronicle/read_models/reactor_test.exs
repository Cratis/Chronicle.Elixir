# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.ReadModels.ReactorTest do
  use ExUnit.Case, async: true

  alias Chronicle.ReadModels.Changeset
  alias Chronicle.ReadModels.Reactors.Handler

  defmodule Account do
    use Chronicle.ReadModels.ReadModel
    defstruct id: "", balance: 0
  end

  defmodule Watcher do
    use Chronicle.ReadModels.Reactor, model: Account

    @impl true
    def on_added(account, _changeset), do: send(self(), {:added, account})

    @impl true
    def on_modified(account, changeset),
      do: send(self(), {:modified, account, changeset.model_key})

    @impl true
    def on_removed(key, _changeset), do: send(self(), {:removed, key})
  end

  defmodule OnlyAdded do
    use Chronicle.ReadModels.Reactor, model: Account, id: "only-added"

    @impl true
    def on_added(_account, _changeset), do: raise("boom")
  end

  defp changeset(type, key, model) do
    %Changeset{
      model_key: key,
      read_model: model,
      removed: type == :removed,
      change_type: type,
      event_sequence_number: 1
    }
  end

  test "introspection" do
    assert Watcher.__chronicle_read_model_reactor__(:model) == Account
    assert OnlyAdded.__chronicle_read_model_reactor__(:id) == "only-added"
    assert Watcher.__chronicle_read_model_reactor__(:event_sequence_id) == "event-log"
  end

  test "changes are routed to the matching callback" do
    account = %Account{id: "a", balance: 5}
    Handler.dispatch(Watcher, changeset(:added, "a", account))
    Handler.dispatch(Watcher, changeset(:modified, "a", account))
    Handler.dispatch(Watcher, changeset(:removed, "a", nil))

    assert_received {:added, ^account}
    assert_received {:modified, ^account, "a"}
    assert_received {:removed, "a"}
  end

  test "an unimplemented callback is ignored and a raising one does not crash the handler" do
    assert Handler.dispatch(OnlyAdded, changeset(:modified, "a", nil)) == :ok

    ExUnit.CaptureLog.capture_log(fn ->
      assert Handler.dispatch(OnlyAdded, changeset(:added, "a", nil)) == :ok
    end)
  end
end
