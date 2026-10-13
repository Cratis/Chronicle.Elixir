# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.ReadModels.Reactor do
  @moduledoc """
  Reacts to **changes of a read model** rather than to events.

  A read model reactor is told when an instance of a read model is added, modified or removed,
  with the instance as it is after the change. Use it for work that follows from state - push
  the new balance to a websocket, invalidate a cache, notify when a threshold is crossed - and
  that should not care which events led there. Mirrors the .NET client's read model reactors.

      defmodule MyApp.Reactors.BalanceWatcher do
        use Chronicle.ReadModels.Reactor, model: MyApp.ReadModels.AccountInfo

        @impl true
        def on_added(account, _changeset), do: Cache.put(account)

        @impl true
        def on_modified(account, changeset) do
          if account.balance < 0, do: Alerts.overdrawn(account, changeset.model_key)
          :ok
        end

        @impl true
        def on_removed(key, _changeset), do: Cache.delete(key)
      end

  Register it with the client (`read_model_reactors: [MyApp.Reactors.BalanceWatcher]`). All three
  callbacks are optional. Return `:ok`; a raised exception is logged and the next change is still
  delivered. The reactor watches the read model through `Chronicle.ReadModels.watch/2`, so it is
  re-established after a reconnect, and it receives changes that happen *while it is running* -
  it is not a replay of history.

  ## Options

    * `:model` - **(required)** the read model module to react to
    * `:id` - a stable identifier, used for logging (defaults to the module name)
    * `:event_sequence_id` - the event sequence of the read model (default `"event-log"`)
  """

  @doc "An instance of the read model was added."
  @callback on_added(
              read_model :: struct() | nil,
              changeset :: Chronicle.ReadModels.Changeset.t()
            ) ::
              any()

  @doc "An instance of the read model was modified."
  @callback on_modified(
              read_model :: struct() | nil,
              changeset :: Chronicle.ReadModels.Changeset.t()
            ) :: any()

  @doc "An instance of the read model was removed. Receives its key."
  @callback on_removed(key :: String.t() | nil, changeset :: Chronicle.ReadModels.Changeset.t()) ::
              any()

  @optional_callbacks on_added: 2, on_modified: 2, on_removed: 2

  defmacro __using__(opts) do
    model = Keyword.fetch!(opts, :model)
    event_sequence_id = Keyword.get(opts, :event_sequence_id, "event-log")

    quote do
      @behaviour Chronicle.ReadModels.Reactor

      @chronicle_rm_reactor_model unquote(model)
      @chronicle_rm_reactor_id Keyword.get(unquote(opts), :id, to_string(__MODULE__))
      @chronicle_rm_reactor_event_sequence unquote(event_sequence_id)

      @doc false
      def __chronicle_read_model_reactor__(:model), do: @chronicle_rm_reactor_model
      def __chronicle_read_model_reactor__(:id), do: @chronicle_rm_reactor_id

      def __chronicle_read_model_reactor__(:event_sequence_id),
        do: @chronicle_rm_reactor_event_sequence
    end
  end
end
