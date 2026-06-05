# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.ReadModels.Resilience do
  @moduledoc false

  # Adds connection-aware resilience to read-model retrieval.
  #
  # Reducer-backed read models are served by an on-demand reduction that requires
  # the reducer's observation stream to be connected on the kernel. For a brief
  # window after every (re)connect the kernel has the reducer registered but not
  # yet marked as connected, and retrieval fails with a transient
  # "reducer is not connected" error. `call/3` waits for the connection to reach
  # the `:registered` phase and retries that transient error so callers get a
  # resilient read instead of a spurious failure.

  alias Chronicle.Connections.Lifecycle

  @registered_wait_timeout 30_000
  @default_attempts 24
  @default_delay 250

  @doc """
  Runs `fun`, retrying the transient "reducer is not connected" error.

  Waits for `lifecycle` (when given) to reach the `:registered` phase before the
  first attempt. `fun` must return `{:ok, term()}` or `{:error, term()}`; any
  other result is returned as-is without retrying.

  ## Options

    * `:attempts` — maximum number of attempts (default `#{@default_attempts}`).
    * `:delay` — delay between attempts in milliseconds (default `#{@default_delay}`).
    * `:wait_timeout` — how long to wait for `:registered` (default `#{@registered_wait_timeout}`).
  """
  @spec call(GenServer.server() | nil, (-> {:ok, term()} | {:error, term()}), keyword()) ::
          {:ok, term()} | {:error, term()} | term()
  def call(lifecycle, fun, opts \\ []) when is_function(fun, 0) do
    wait_until_registered(lifecycle, Keyword.get(opts, :wait_timeout, @registered_wait_timeout))

    attempt(
      fun,
      Keyword.get(opts, :attempts, @default_attempts),
      Keyword.get(opts, :delay, @default_delay)
    )
  end

  @doc """
  Returns `true` when `error` is the transient reducer-not-connected error the
  kernel returns during the post-connect settle window.
  """
  @spec reducer_not_connected?(term()) :: boolean()
  def reducer_not_connected?(%GRPC.RPCError{status: 2, message: message}) when is_binary(message),
    do: String.contains?(message, "is not connected")

  def reducer_not_connected?(_), do: false

  defp attempt(fun, attempts_left, delay) do
    case fun.() do
      {:error, error} = result ->
        if attempts_left > 1 and reducer_not_connected?(error) do
          Process.sleep(delay)
          attempt(fun, attempts_left - 1, delay)
        else
          result
        end

      result ->
        result
    end
  end

  defp wait_until_registered(nil, _timeout), do: :ok

  defp wait_until_registered(lifecycle, timeout) do
    Lifecycle.wait_until(lifecycle, :registered, timeout)
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
  end
end
