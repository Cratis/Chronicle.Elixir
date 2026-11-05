# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Observers.PageDeliveryOptions do
  @moduledoc false

  # Reads the `:batch_size` option of `use Chronicle.Reactors.Reactor` and
  # `use Chronicle.Reducers.Reducer`:
  #
  #   * `:max_events` - the most events a page may hold
  #   * `:max_bytes` - the most bytes a page may hold
  #   * `:max_delay_milliseconds` - how long the kernel may wait to fill a page (default 0)
  #   * `:max_concurrency` - reducers: how many event sources of one page are reduced at the
  #     same time (default: the number of schedulers online)
  #
  # A bound that is not given is sent as 0, which leaves it to the kernel's default.

  @known [:max_events, :max_bytes, :max_delay_milliseconds, :max_concurrency]

  @doc """
  Builds the `PageDelivery` registration field (of the given contracts module) that opts the
  observer in to pages.
  """
  @spec to_wire(module(), keyword()) :: struct()
  def to_wire(module, opts) do
    opts = validate!(opts)

    struct(module,
      Enabled: true,
      MaxEventsPerPage: Keyword.get(opts, :max_events, 0),
      MaxBytesPerPage: Keyword.get(opts, :max_bytes, 0),
      MaxDelayMilliseconds: Keyword.get(opts, :max_delay_milliseconds, 0)
    )
  end

  @doc "How many event sources of one page a reducer reduces at the same time."
  @spec max_concurrency(keyword()) :: pos_integer()
  def max_concurrency(opts) do
    case Keyword.get(validate!(opts), :max_concurrency) do
      nil -> System.schedulers_online()
      max -> max
    end
  end

  defp validate!(opts) when is_list(opts) do
    Enum.each(opts, fn
      {key, value} when key in @known and is_integer(value) and value >= 0 ->
        :ok

      other ->
        raise ArgumentError,
              "invalid :batch_size option #{inspect(other)}; expected non-negative integers for " <>
                Enum.map_join(@known, ", ", &inspect/1)
    end)

    if Keyword.get(opts, :max_concurrency) == 0 do
      raise ArgumentError, ":batch_size :max_concurrency must be at least 1"
    end

    opts
  end
end
