# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Testing.Integration do
  @moduledoc """
  Helpers for integration specs that need a **real** running kernel — because
  they exercise something `Chronicle.Testing.InMemoryKernel` does not model
  (the server-side projection engine, `closes_stream` constraints, and the
  rest listed on its moduledoc).

  `setup_isolated_client/2` gives every integration test its own event store and
  namespace, so tests run concurrently without seeing one another's events, and
  `wait_for_observers/2` waits for every affected observer deterministically
  instead of sleeping.

  ## Usage

      @moduletag :integration

      setup do
        {:ok, client} =
          Chronicle.Testing.Integration.setup_isolated_client(
            event_types: [MyApp.Events.AccountOpened],
            reducers: [MyApp.Reducers.AccountReducer]
          )

        %{chronicle: client}
      end

      test "appends and projects", %{chronicle: client} do
        {:ok, result} =
          Chronicle.EventSequences.EventLog.append_with_result(
            "account-1", %AccountOpened{}, client: client
          )

        :ok = Chronicle.Testing.Integration.wait_for_observers(result.sequence_number, client: client)
      end

  Removing the event store/namespace afterward is not possible yet: Chronicle's
  `EventStores`/`Namespaces` contracts have no delete RPC (tracked upstream in
  Cratis/Chronicle). `setup_isolated_client/2` stops the client on `on_exit`, but
  the store and namespace it created are left behind.
  """

  alias Chronicle.Client
  alias Chronicle.EventSequences.EventLog

  @default_registration_timeout 10_000

  @doc """
  Starts a real `Chronicle.Client` against the connection string in
  `CHRONICLE_INTEGRATION_CONNECTION_STRING` (or `opts[:connection_string]`),
  with a unique `:event_store` and `:namespace` so this test never collides with
  another test's events. Waits for registration, and stops the client on
  `ExUnit.Callbacks.on_exit/1`.

  `opts` accepts every `Chronicle.Client` option; `:event_store`/`:namespace`
  default to a name unique to this call. `client` is the registered client name
  (default: `Chronicle.Client`).

  Returns `{:ok, client}` or `{:error, reason}`.
  """
  @spec setup_isolated_client(keyword(), atom()) :: {:ok, atom()} | {:error, term()}
  def setup_isolated_client(opts \\ [], client \\ Chronicle.Client) do
    unique = System.unique_integer([:positive])

    client_opts =
      opts
      |> Keyword.put_new(:event_store, "integration-#{unique}")
      |> Keyword.put_new(:namespace, "ns-#{unique}")
      |> Keyword.put_new(
        :connection_string,
        System.get_env("CHRONICLE_INTEGRATION_CONNECTION_STRING")
      )
      |> Keyword.put(:name, client)

    timeout = Keyword.get(opts, :registration_timeout, @default_registration_timeout)

    with {:ok, _pid} <- Client.start_link(client_opts),
         :ok <- Client.await_registration(client, timeout) do
      ExUnit.Callbacks.on_exit(fn -> stop(client) end)
      {:ok, client}
    end
  end

  @doc """
  Waits for every observer affected by events up to `sequence_number` to reach it
  or fail — no sleeps. Delegates to
  `Chronicle.EventSequences.EventLog.wait_for_sequence_number/2`.
  """
  @spec wait_for_observers(non_neg_integer(), keyword()) :: {:ok, map()} | {:error, term()}
  defdelegate wait_for_observers(sequence_number, opts \\ []),
    to: EventLog,
    as: :wait_for_sequence_number

  defp stop(client) do
    case Process.whereis(client) do
      nil -> :ok
      pid -> if Process.alive?(pid), do: Supervisor.stop(pid)
    end
  catch
    :exit, _ -> :ok
  end
end
