# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Connections.PrivateKeySigner do
  @moduledoc false
  use GenServer

  # OTP 28 ssl:key/0 accepts a map with algorithm, sign_fun and sign_opts.
  # https://github.com/erlang/otp/blob/OTP-28.5/lib/ssl/src/ssl.erl
  # The closure captures only a pid. In particular neither the credential nor
  # any SSL/dependency process can inspect the private key through the fun.
  def start(private_key, algorithm) do
    # Transfer the private ETS table, not a key-bearing GenServer startup
    # argument or message. An init failure must not print the key in a crash.
    table = :ets.new(__MODULE__, [:private])
    true = :ets.insert(table, {:key, private_key})
    {:ok, pid} = GenServer.start(__MODULE__, self())
    true = :ets.give_away(table, pid, :key)
    :ok = GenServer.call(pid, :ready)

    %{
      algorithm: algorithm,
      sign_fun: fn data, digest, options -> sign(pid, data, digest, options) end,
      sign_opts: []
    }
  end

  defp sign(pid, data, digest, options) do
    case GenServer.call(pid, {:sign, data, digest, options}, :infinity) do
      {:ok, signature} -> signature
      :error -> raise ArgumentError, "client certificate signing failed"
    end
  end

  @impl true
  def init(owner) do
    {:ok, {nil, Process.monitor(owner)}}
  end

  @impl true
  def handle_call(:ready, _from, {table, _monitor} = state) when is_reference(table) do
    {:reply, :ok, state}
  end

  def handle_call({:sign, data, digest, options}, _from, {table, _monitor} = state) do
    # Never let a signing error propagate into a crash report with key-bearing
    # stack arguments. Only a signature or an opaque error leaves this process.
    result =
      try do
        [{:key, key}] = :ets.lookup(table, :key)
        {:ok, :public_key.sign(data, digest, key, options)}
      catch
        _, _ -> :error
      end

    {:reply, result, state}
  end

  @impl true
  def handle_info({:"ETS-TRANSFER", table, _owner, :key}, {_old_table, monitor}) do
    {:noreply, {table, monitor}}
  end

  def handle_info({:DOWN, monitor, :process, _owner, _reason}, {_table, monitor} = state) do
    {:stop, :normal, state}
  end

  @impl true
  def format_status(%{state: _state} = status) do
    status
    |> Map.put(:state, :redacted)
    |> Map.replace_lazy(:message, fn _ -> :redacted end)
    |> Map.replace_lazy(:log, fn _ -> :redacted end)
    |> Map.replace_lazy(:reason, fn _ -> :redacted end)
  end
end
