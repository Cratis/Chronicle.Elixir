# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Observers.ReconnectBackoff do
  @moduledoc false

  # Decides how long one reactor or reducer waits before opening its observation
  # stream again after it ended. Mirrors the .NET client's
  # ObservationReconnectBackoff.
  #
  # A fixed delay is right for one observer and wrong for many: seventy reactors
  # whose streams fail together come back together, every two seconds, against a
  # kernel that is still busy. So each stream that ends without having worked
  # doubles the wait, up to a ceiling, and every wait lands at random in the upper
  # half of it, so a herd spreads out.
  #
  # The wait starts over once a stream has worked: it delivered something, or it
  # stayed open long enough to have been established. A stream the kernel closes
  # after a long life therefore comes back after the base delay. A base delay of
  # zero is used as it is.
  #
  # This is a plain value threaded through the handler's state; it starts no
  # process and reads the clock and the random source only through the functions
  # it was given, so it can be driven deterministically.

  # The wait after a stream that had worked.
  @default_base_delay 2_000

  # The longest wait, however often streams end.
  @default_max_delay 60_000

  # How long a stream must stay open to count as having worked. It must be longer
  # than the kernel takes to give up establishing a stream: the kernel asks a busy
  # observer again on the same stream, up to four attempts of a thirty-second
  # grain call each, before it fails the stream. A shorter threshold would count
  # every such stream as having worked and start the wait over at the base delay -
  # exactly for the herd of slow subscribes the backoff exists for.
  @default_healthy_stream_duration 180_000

  @max_exponent 30

  @options [:base_delay, :max_delay, :healthy_stream_duration, :jitter_fun, :now_fun]

  defstruct base_delay: @default_base_delay,
            max_delay: @default_max_delay,
            healthy_stream_duration: @default_healthy_stream_duration,
            jitter_fun: nil,
            now_fun: nil,
            ended_without_working: 0,
            opened_at: nil

  @type t :: %__MODULE__{
          base_delay: non_neg_integer(),
          max_delay: non_neg_integer(),
          healthy_stream_duration: non_neg_integer(),
          jitter_fun: (-> float()),
          now_fun: (-> integer()),
          ended_without_working: non_neg_integer(),
          opened_at: integer() | nil
        }

  @doc """
  Builds a backoff from the `:observation_reconnect` options.

    * `:base_delay` — milliseconds to wait after a stream that had worked (default `2_000`).
    * `:max_delay` — the longest wait in milliseconds (default `60_000`).
    * `:healthy_stream_duration` — milliseconds a stream must stay open to count as
      having worked (default `180_000`).
    * `:jitter_fun` — returns a float in `[0, 1)` choosing where in the upper half of
      the wait this one lands (default `:rand.uniform/0`).
    * `:now_fun` — returns the current monotonic time in milliseconds.
  """
  @spec new(keyword()) :: t()
  def new(options \\ []) do
    options = Keyword.validate!(options, @options)

    %__MODULE__{
      base_delay: non_neg!(options, :base_delay, @default_base_delay),
      max_delay: non_neg!(options, :max_delay, @default_max_delay),
      healthy_stream_duration:
        non_neg!(options, :healthy_stream_duration, @default_healthy_stream_duration),
      jitter_fun: Keyword.get(options, :jitter_fun) || (&:rand.uniform/0),
      now_fun: Keyword.get(options, :now_fun) || fn -> System.monotonic_time(:millisecond) end
    }
  end

  @doc "Records that a new observation stream is being opened."
  @spec stream_opened(t()) :: t()
  def stream_opened(%__MODULE__{} = backoff), do: %{backoff | opened_at: backoff.now_fun.()}

  @doc "Records that the open stream delivered something, which proves it was established."
  @spec stream_delivered(t()) :: t()
  def stream_delivered(%__MODULE__{} = backoff), do: %{backoff | ended_without_working: 0}

  @doc """
  Returns how long to wait, in milliseconds, before opening the stream again now
  that the open one has ended, together with the updated backoff.
  """
  @spec next_delay(t()) :: {non_neg_integer(), t()}
  def next_delay(%__MODULE__{base_delay: 0} = backoff), do: {0, backoff}

  def next_delay(%__MODULE__{} = backoff) do
    ended_without_working =
      if stayed_open_long_enough?(backoff), do: 1, else: backoff.ended_without_working + 1

    exponent = min(ended_without_working - 1, @max_exponent)
    ceiling = min(backoff.max_delay, backoff.base_delay * Integer.pow(2, exponent))
    jitter = 0.5 + 0.5 * clamp(backoff.jitter_fun.())

    {trunc(ceiling * jitter), %{backoff | ended_without_working: ended_without_working}}
  end

  defp stayed_open_long_enough?(%{opened_at: nil}), do: false

  defp stayed_open_long_enough?(backoff),
    do: backoff.now_fun.() - backoff.opened_at >= backoff.healthy_stream_duration

  defp clamp(value) when value < 0, do: 0.0
  defp clamp(value) when value > 1, do: 1.0
  defp clamp(value), do: value

  defp non_neg!(options, key, default) do
    case Keyword.get(options, key, default) do
      value when is_integer(value) and value >= 0 ->
        value

      value ->
        raise ArgumentError,
              "#{inspect(key)} must be a non-negative integer of milliseconds, got: #{inspect(value)}"
    end
  end
end
