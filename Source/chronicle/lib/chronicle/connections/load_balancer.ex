# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Connections.LoadBalancer do
  @moduledoc """
  Selects a Chronicle server address to connect to from a resolved candidate list.

  `Chronicle.Connections.Connection` re-resolves its configured (or DNS
  SRV-resolved, via `Chronicle.Connections.DnsResolver`) addresses on every
  connect/reconnect attempt and asks `select/4` to pick one, according to the
  connection string's `loadBalancer` strategy:

    * `:least_connections` (the default) — probes every candidate's
      `GET /connections/count` HTTP endpoint on the Chronicle kernel and picks
      the address reporting the fewest active connections, breaking ties
      randomly. A small random jitter is slept before probing so a fleet of
      clients reconnecting at the same moment doesn't stampede every
      candidate host simultaneously. The winner is then best-effort informed
      via `POST /connections/reserve`, so other clients racing to connect at
      the same time see an up-to-date count. If every probe fails (e.g. none
      of the candidates expose the endpoint), selection falls back to
      `:random` rather than failing the connection attempt outright. The
      actual HTTP calls live in `Chronicle.Connections.LoadBalancer.HttpProbe`.
    * `:round_robin` — cycles through the candidates in order. The starting
      point is a random offset chosen once per `Connection` process (not
      index `0`), so a fleet of clients doesn't all dial the first host first.
    * `:random` — picks uniformly at random on every attempt.

  ## Testing

  The HTTP probe used by `:least_connections` is injectable via the
  `:probe_fun` option on `Chronicle.Connections.Connection`, mirroring the
  `:connect_fun`/`:disconnect_fun` seam already used to fake the gRPC channel.
  """

  require Logger

  alias Chronicle.Connections.ConnectionString
  alias Chronicle.Connections.ConnectionString.ServerAddress
  alias Chronicle.Connections.LoadBalancer.HttpProbe

  @type probe_action :: :count | :reserve
  @type probe_fun ::
          (probe_action(), ServerAddress.t(), ConnectionString.t() ->
             {:ok, term()} | {:error, term()})

  @jitter_max_ms 25

  @doc """
  Selects one address from `addresses` according to
  `connection_string.load_balancer`.

  `round_robin_counter` is an ever-incrementing integer owned by the calling
  `Connection` process — this module holds no state of its own, since the
  counter (and any future strategy state) belongs to the one `Connection`
  GenServer it is scoped to.

  Returns `{:error, :no_addresses}` when `addresses` is empty.
  """
  @spec select([ServerAddress.t()], ConnectionString.t(), integer(), probe_fun()) ::
          {:ok, ServerAddress.t()} | {:error, :no_addresses}
  def select([], _connection_string, _round_robin_counter, _probe_fun) do
    {:error, :no_addresses}
  end

  def select([address], _connection_string, _round_robin_counter, _probe_fun) do
    {:ok, address}
  end

  def select(addresses, connection_string, round_robin_counter, probe_fun) do
    case connection_string.load_balancer do
      :round_robin -> {:ok, round_robin_pick(addresses, round_robin_counter)}
      :random -> {:ok, Enum.random(addresses)}
      :least_connections -> {:ok, least_connections_pick(addresses, connection_string, probe_fun)}
    end
  end

  @doc """
  Default `:probe_fun` implementation, delegating to
  `Chronicle.Connections.LoadBalancer.HttpProbe`.
  """
  @spec default_probe(probe_action(), ServerAddress.t(), ConnectionString.t()) ::
          {:ok, term()} | {:error, term()}
  defdelegate default_probe(action, address, connection_string), to: HttpProbe, as: :request

  defp round_robin_pick(addresses, counter) do
    Enum.at(addresses, Integer.mod(counter, length(addresses)))
  end

  defp least_connections_pick(addresses, connection_string, probe_fun) do
    Process.sleep(:rand.uniform(@jitter_max_ms))

    reachable =
      addresses
      |> Enum.map(&{&1, probe_count(&1, connection_string, probe_fun)})
      |> Enum.filter(fn {_address, count} -> count != :error end)

    case reachable do
      [] ->
        Logger.warning(
          "Chronicle least-connections probe failed for every candidate; picking randomly"
        )

        Enum.random(addresses)

      reachable ->
        min_count = reachable |> Enum.map(&elem(&1, 1)) |> Enum.min()

        selected =
          reachable
          |> Enum.filter(fn {_address, count} -> count == min_count end)
          |> Enum.map(&elem(&1, 0))
          |> Enum.random()

        reserve(selected, connection_string, probe_fun)
        selected
    end
  end

  defp probe_count(address, connection_string, probe_fun) do
    case probe_fun.(:count, address, connection_string) do
      {:ok, count} when is_integer(count) -> count
      _other -> :error
    end
  end

  defp reserve(address, connection_string, probe_fun) do
    case probe_fun.(:reserve, address, connection_string) do
      {:ok, _reply} ->
        :ok

      {:error, reason} ->
        Logger.debug(
          "Chronicle least-connections reserve failed for #{address.host}:#{address.port}: " <>
            inspect(reason)
        )

        :ok
    end
  end
end
