# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Cratis.Chronicle.Registration.AcceptedRegistration do
  @moduledoc false

  # Waits until the kernel has applied the projections it accepted from a registrant, mirroring the
  # .NET client's `Projections.WaitForAcceptedRegistration`.
  #
  # The kernel accepts a registration and answers at once; applying it happens in the background.
  # Polling with short calls, instead of one long call, is what keeps a busy kernel from timing the
  # client out. The wait is bounded and, when it ends, the registration is still the kernel's to
  # apply. A kernel that does not accept registrations answers after applying them and has no status
  # to wait for (`UNIMPLEMENTED`).

  require Logger

  alias Cratis.Chronicle.Contracts.Projections.{GetRegistrationStatusRequest, Projections}

  @initial_delay 50
  @max_delay 2_000
  @max_wait 300_000
  @unimplemented 12

  @doc """
  Polls the registration status of `registrant` until it is not pending.

  Returns `:ok` once the kernel applied it, when the kernel has no status to give, or when the wait
  ended with the registration still being applied. Returns `{:error, {:projection_registration_not_applied,
  registrant, failure}}` when the kernel accepted the registration but could not apply it, and
  `{:error, reason}` when the status could not be asked.

  Options: `:max_wait` (milliseconds, default 5 minutes) and the test seams `:sleep_fun` and `:now_fun`.
  """
  @spec wait(GRPC.Channel.t(), String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def wait(_channel, _event_store, "", _opts), do: :ok

  def wait(channel, event_store, registrant, opts) do
    state = %{
      channel: channel,
      event_store: event_store,
      registrant: registrant,
      max_wait: Keyword.get(opts, :max_wait, @max_wait),
      sleep_fun: Keyword.get(opts, :sleep_fun, &Process.sleep/1),
      now_fun: Keyword.get(opts, :now_fun, fn -> System.monotonic_time(:millisecond) end)
    }

    poll(state, @initial_delay, state.now_fun.())
  end

  defp poll(state, delay, started) do
    request =
      struct(GetRegistrationStatusRequest,
        EventStore: state.event_store,
        Registrant: state.registrant
      )

    case Projections.Stub.get_registration_status(state.channel, request) do
      {:ok, status} ->
        decide(state, Map.get(status, :State), status, delay, started)

      {:error, %GRPC.RPCError{status: @unimplemented}} ->
        :ok

      {:error, reason} ->
        {:error, {:registration_status, reason}}
    end
  end

  defp decide(_state, applied, _status, _delay, _started) when applied in [:Applied, 1], do: :ok

  defp decide(state, failed, status, _delay, _started) when failed in [:Failed, 2] do
    {:error,
     {:projection_registration_not_applied, state.registrant, Map.get(status, :Failure, "")}}
  end

  defp decide(state, _pending, _status, delay, started) do
    if state.now_fun.() - started > state.max_wait do
      Logger.warning(
        "The kernel accepted the projections registered by '#{state.registrant}' but has not " <>
          "finished applying them after #{state.max_wait}ms; carrying on, the kernel keeps applying them"
      )

      :ok
    else
      state.sleep_fun.(delay)
      poll(state, min(delay * 2, @max_delay), started)
    end
  end
end
