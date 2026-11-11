# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Observers.StreamReconnect do
  @moduledoc false

  # The timer a reactor or reducer handler waits on before reopening its
  # observation stream, shared by both handlers the way BatchRunner is.
  #
  # The handler state carries `:backoff` (a Chronicle.Observers.ReconnectBackoff),
  # `:send_after_fun` and `:reconnect_timer`. Each timer is tagged with a fresh
  # reference and fires `{:reopen, ref}`. Cancelling a timer that has already
  # fired does not take its message back out of the mailbox, so a handler acts on
  # a `{:reopen, ref}` only while `ref` is still its current timer: a stale one
  # would otherwise tear down the stream the handler opened in the meantime.

  alias Chronicle.Observers.ReconnectBackoff

  @doc """
  Schedules a reopen after the next backoff wait, unless one is already pending,
  so two reports of the same ending cannot schedule twice or grow the wait twice.
  """
  @spec schedule(map()) :: map()
  def schedule(%{reconnect_timer: timer} = state) when not is_nil(timer), do: state

  def schedule(state) do
    {delay, backoff} = ReconnectBackoff.next_delay(state.backoff)
    ref = make_ref()
    timer = state.send_after_fun.({:reopen, ref}, delay)
    %{state | reconnect_timer: {timer, ref}, backoff: backoff}
  end

  @doc "Returns whether `ref` tags the timer the handler is currently waiting on."
  @spec current?(map(), reference()) :: boolean()
  def current?(%{reconnect_timer: {_timer, ref}}, ref), do: true
  def current?(_state, _ref), do: false

  @doc "Cancels the pending timer, if any. A message it already sent is left to `current?/2`."
  @spec cancel(map()) :: map()
  def cancel(%{reconnect_timer: {timer, _ref}} = state) do
    Process.cancel_timer(timer)
    %{state | reconnect_timer: nil}
  end

  def cancel(state), do: %{state | reconnect_timer: nil}
end
