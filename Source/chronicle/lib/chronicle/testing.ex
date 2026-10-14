# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Testing do
  @moduledoc """
  Testing support for applications built on Chronicle: an in-memory fake kernel,
  deterministic helpers, and assertions — so a spec can exercise commands,
  reactors, reducers, constraints and concurrency without a running kernel.

  ## Usage

      {:ok, client} =
        Chronicle.Testing.start_supervised_client(
          event_types: [MyApp.Events.AccountOpened],
          reducers: [MyApp.Reducers.AccountReducer]
        )

      :ok = Chronicle.EventSequences.EventLog.append("account-1", %AccountOpened{}, client: client)
      :ok = Chronicle.Testing.wait_for_observers(client)

      {:ok, %MyApp.ReadModels.Account{} = account} =
        Chronicle.Testing.read_model(client, MyApp.Reducers.AccountReducer, "account-1")

      Chronicle.Testing.stop_supervised_client(client)

  Prefer `Chronicle.Testing.Case` in ExUnit tests, which does this setup/teardown
  for you and is safe under `async: true`.

  ## What runs for real, and what is modeled

  `start_supervised_client/1` starts a real `Chronicle.Client` pointed at a
  `Chronicle.Testing.InMemoryKernel` instead of a socket — so command validation,
  `Chronicle.EventSequences.EventLog`'s append/read/unit-of-work code,
  constraint declarations, and concurrency scopes all run completely unchanged.
  Reactors and reducers do **not** run through the real gRPC observation stream
  (the in-memory kernel does not simulate bidirectional streaming): they run
  synchronously, in a separate `Chronicle.Testing.Dispatcher` process, right after
  each committed append, by calling the exact same `Chronicle.Reactors.Dispatch`
  and `Chronicle.Reducers.Dispatch` modules the real stream-handling processes
  use.

  Reducer read model state is kept by the dispatcher, keyed by event source id —
  `read_model/3` reads it directly; there is no in-memory `ReadModels`/`Projections`
  query surface. Projection read models (declared with `from`/`join`/`removed_with`,
  not a reducer) are evaluated by `Chronicle.Testing.Projections` for the supported
  subset.

  `closes_stream` constraints and any RPC outside the list in
  `Chronicle.Testing.InMemoryKernel`'s moduledoc return
  `{:error, {:not_supported_in_memory, rpc}}` — reach for
  `Chronicle.Testing.Integration` and a real kernel for those.
  """

  alias Chronicle.Events.Constraints
  alias Chronicle.Testing.{Dispatcher, InMemoryKernel}

  @registry_prefix __MODULE__

  @doc """
  Starts a `Chronicle.Client` supervision tree against an in-memory kernel, and a
  dispatcher that runs the given reactors and reducers synchronously after every
  committed append.

  ## Options

    * `:name` — the client name other calls address it by (default: a unique
      generated atom)
    * `:event_store` / `:namespace` — default to a unique generated name /
      `"Default"`
    * `:event_types` — event type modules to register
    * `:event_sources` — `Chronicle.EventSources.EventSource` modules to register
    * `:constraints` — standalone constraint modules (each
      `use Chronicle.Events.Constraint`); combined with constraints declared on
      `:event_types`
    * `:reactors` — reactor modules run synchronously by the dispatcher
    * `:reducers` — reducer modules run synchronously by the dispatcher
    * `:projections` — read model modules evaluated by
      `Chronicle.Testing.Projections` instead of a reducer (optional; this
      testing kernel does not register or run the server-side projection engine)

  Returns `{:ok, client}`, where `client` is the name to pass as `:client` to
  `Chronicle.EventSequences.EventLog`, `Chronicle.append/3`, etc.
  """
  @spec start_supervised_client(keyword()) :: {:ok, atom()} | {:error, term()}
  def start_supervised_client(opts \\ []) do
    event_store =
      Keyword.get(opts, :event_store, "test-store-#{System.unique_integer([:positive])}")

    namespace = Keyword.get(opts, :namespace, "Default")
    event_types = Keyword.get(opts, :event_types, [])
    event_sources = Keyword.get(opts, :event_sources, [])
    constraint_modules = Keyword.get(opts, :constraints, [])
    reactors = Keyword.get(opts, :reactors, [])
    reducers = Keyword.get(opts, :reducers, [])

    name =
      Keyword.get(
        opts,
        :name,
        Module.concat(Chronicle.Testing.Client, "C#{System.unique_integer([:positive])}")
      )

    constraints =
      Constraints.from_event_types(event_types) ++
        Constraints.from_constraint_modules(constraint_modules)

    {:ok, kernel} =
      InMemoryKernel.start_link(
        event_store: event_store,
        namespace: namespace,
        event_types: event_types,
        constraints: constraints
      )

    connect_fun = fn _target, _grpc_opts -> {:ok, InMemoryKernel.channel(kernel)} end
    disconnect_fun = fn _channel -> :ok end

    with {:ok, client_sup} <-
           Chronicle.Client.start_link(
             name: name,
             connection_string: "chronicle://in-memory",
             event_store: event_store,
             namespace: namespace,
             event_types: event_types,
             event_sources: event_sources,
             constraints: constraint_modules,
             discover: false,
             # The in-memory kernel answers no discovery queries, and there is nothing
             # registered before the spec to drift from.
             drift_policy: :ignore,
             warn_defaulted_ids: false,
             connect_fun: connect_fun,
             disconnect_fun: disconnect_fun
           ),
         :ok <- Chronicle.Client.await_registration(name, 5_000) do
      {:ok, dispatcher} =
        Dispatcher.start_link(client: name, reactors: reactors, reducers: reducers)

      :ok = InMemoryKernel.subscribe(kernel, dispatcher)

      put_registry(name, %{kernel: kernel, dispatcher: dispatcher, client_sup: client_sup})
      {:ok, name}
    else
      {:error, reason} ->
        GenServer.stop(kernel)
        {:error, reason}
    end
  end

  @doc """
  Stops a client started by `start_supervised_client/1`: the dispatcher, the
  `Chronicle.Client` supervision tree, and the in-memory kernel, in that order.
  """
  @spec stop_supervised_client(atom()) :: :ok
  def stop_supervised_client(client) do
    case fetch_registry(client) do
      {:ok, %{kernel: kernel, dispatcher: dispatcher, client_sup: client_sup}} ->
        safe_stop(dispatcher, &GenServer.stop/1)
        safe_stop(client_sup, &Supervisor.stop/1)
        safe_stop(kernel, &GenServer.stop/1)
        delete_registry(client)
        :ok

      :error ->
        :ok
    end
  end

  @doc """
  Waits for every reactor and reducer the client's dispatcher owns to finish
  processing every append committed so far. Deterministic — no sleeps: it sends
  a synchronous call to the dispatcher, which can only answer once its mailbox
  (where the kernel's append notifications arrive, in order) has drained up to
  this point.

  Returns `:ok`, or `{:error, failures}` when a reactor or reducer raised while
  processing an event (each failure is `{:reactor | :reducer, module, reason}`).
  """
  @spec wait_for_observers(atom()) :: :ok | {:error, [term()]}
  def wait_for_observers(client) do
    with {:ok, %{dispatcher: dispatcher}} <- fetch_registry(client) do
      :ok = Dispatcher.ping(dispatcher)

      case Dispatcher.failures(dispatcher) do
        [] -> :ok
        failures -> {:error, failures}
      end
    end
  end

  @doc """
  Reads the read model state a reducer has built for `key` (typically an event
  source id). Call `wait_for_observers/1` first if the append that produced it
  might not have been processed yet.
  """
  @spec read_model(atom(), module(), String.t()) :: {:ok, struct() | nil}
  def read_model(client, reducer_module, key) do
    with {:ok, %{dispatcher: dispatcher}} <- fetch_registry(client) do
      Dispatcher.read_model(dispatcher, reducer_module, key)
    end
  end

  @doc """
  Returns every event appended for `event_source_id`, decoded into
  `Chronicle.Events.AppendedEvent` structs, in append order.
  """
  @spec appended_events(atom(), String.t()) :: [Chronicle.Events.AppendedEvent.t()]
  def appended_events(client, event_source_id) do
    with {:ok, %{kernel: kernel}} <- fetch_registry(client) do
      event_types = InMemoryKernel.event_types(kernel)

      kernel
      |> InMemoryKernel.wire_events_for(event_source_id)
      |> Enum.map(&Chronicle.Events.AppendedEvent.from_wire(&1, event_types))
    end
  end

  @doc false
  @spec kernel_for(atom()) :: GenServer.server() | nil
  def kernel_for(client) do
    case fetch_registry(client) do
      {:ok, %{kernel: kernel}} -> kernel
      :error -> nil
    end
  end

  defp safe_stop(pid, stop_fun) do
    if Process.alive?(pid), do: stop_fun.(pid)
  catch
    :exit, _ -> :ok
  end

  # Each client's registry entry lives under its own persistent_term key (never a
  # shared map): concurrent async tests each own a distinct key, so there is no
  # read-modify-write race between them. :persistent_term.put/get/erase on a
  # single key are independently atomic.
  defp put_registry(client, value), do: :persistent_term.put({@registry_prefix, client}, value)

  defp fetch_registry(client) do
    case :persistent_term.get({@registry_prefix, client}, :not_found) do
      :not_found -> :error
      value -> {:ok, value}
    end
  end

  defp delete_registry(client), do: :persistent_term.erase({@registry_prefix, client})
end
