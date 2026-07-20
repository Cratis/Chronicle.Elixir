# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Connections.DnsResolver do
  @moduledoc """
  Resolves `chronicle+srv://` connection strings via DNS SRV lookups.

  A Chronicle Kernel deployment that publishes a DNS SRV record can be
  addressed with a single `chronicle+srv://<host>` connection string instead of
  an explicit multi-host list. `Chronicle.Connections.Connection` re-resolves
  the record on every connect/reconnect attempt — through the injectable
  `:resolve_fun` option, mirroring the `:connect_fun`/`:disconnect_fun` seam
  already used to fake the gRPC channel in tests — so membership changes are
  picked up automatically without a separate background refresh loop.

  The query name is `_chronicle._tcp.<host>`, following the standard SRV
  naming convention (`_service._proto.name`). Resolution goes through the
  system resolver via `:inet_res` by default; passing a `srvNameServer`
  connection string option (a `"host"` or `"host:port"` string) queries that
  name server directly instead.

  Resolved addresses are sorted ascending by priority, then descending by
  weight, matching standard SRV record selection order (lower priority first;
  among equal priorities, higher weight first).
  """

  alias Chronicle.Connections.ConnectionString.ServerAddress

  @service_prefix "_chronicle._tcp."
  @default_dns_port 53

  @type srv_record ::
          {non_neg_integer(), non_neg_integer(), non_neg_integer(), charlist() | String.t()}

  @doc """
  Resolves the SRV record for `host`, optionally via a specific `name_server`.

  `name_server` is a `"host"` or `"host:port"` string; `nil` (the default) uses
  the system resolver. Returns `{:ok, addresses}` sorted per the module doc, or
  `{:error, reason}` when the lookup fails or returns no records.
  """
  @spec resolve(String.t(), String.t() | nil) :: {:ok, [ServerAddress.t()]} | {:error, term()}
  def resolve(host, name_server \\ nil) do
    name = @service_prefix <> host

    case lookup(name, name_server) do
      {:ok, []} ->
        {:error, {:srv_no_records, name}}

      {:ok, records} ->
        {:ok, to_addresses(records)}

      {:error, reason} ->
        {:error, {:srv_lookup_failed, name, reason}}
    end
  end

  @doc """
  Converts raw SRV answer tuples (`{priority, weight, port, target}`) into
  sorted `ServerAddress` structs.

  Exposed separately from `resolve/2` so the selection/ordering logic can be
  unit tested without touching real DNS.
  """
  @spec to_addresses([srv_record()]) :: [ServerAddress.t()]
  def to_addresses(records) do
    records
    |> Enum.sort_by(fn {priority, weight, _port, _target} -> {priority, -weight} end)
    |> Enum.map(fn {_priority, _weight, port, target} ->
      %ServerAddress{host: to_string(target), port: port}
    end)
  end

  defp lookup(name, nil) do
    case :inet_res.getbyname(String.to_charlist(name), :srv) do
      {:ok, {:hostent, _name, _aliases, :srv, _length, addr_list}} -> {:ok, addr_list}
      {:error, reason} -> {:error, reason}
    end
  end

  defp lookup(name, name_server) do
    with {:ok, nameserver} <- resolve_name_server(name_server) do
      case :inet_res.resolve(String.to_charlist(name), :in, :srv, nameservers: [nameserver]) do
        {:ok, dns_msg} ->
          {:ok, dns_msg |> :inet_dns.msg(:anlist) |> Enum.map(&:inet_dns.rr(&1, :data))}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp resolve_name_server(name_server) do
    {host, port} = split_host_port(name_server)

    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, ip} ->
        {:ok, {ip, port}}

      {:error, _reason} ->
        case :inet.gethostbyname(String.to_charlist(host)) do
          {:ok, {:hostent, _name, _aliases, _addrtype, _length, [ip | _]}} ->
            {:ok, {ip, port}}

          {:error, reason} ->
            {:error, {:srv_name_server_lookup_failed, host, reason}}
        end
    end
  end

  defp split_host_port(name_server) do
    case String.split(name_server, ":", parts: 2) do
      [host, port_string] -> {host, String.to_integer(port_string)}
      [host] -> {host, @default_dns_port}
    end
  end
end
