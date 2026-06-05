# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Transactions.UnitOfWorkManager do
  @moduledoc false

  alias Chronicle.CorrelationId
  alias Chronicle.Transactions.{NoUnitOfWorkStarted, UnitOfWork}

  @process_key {__MODULE__, :current}
  @table __MODULE__

  @spec begin(keyword()) :: UnitOfWork.t()
  def begin(opts \\ []) do
    correlation_id = normalize_correlation_id(Keyword.get(opts, :correlation_id))

    {:ok, unit_of_work} =
      UnitOfWork.start_link(Keyword.put(opts, :correlation_id, correlation_id))

    set_current(unit_of_work)
  end

  @spec current() :: UnitOfWork.t()
  def current do
    case Process.get(@process_key) do
      unit_of_work when is_pid(unit_of_work) -> unit_of_work
      _ -> raise NoUnitOfWorkStarted
    end
  end

  @spec has_current?() :: boolean()
  def has_current?, do: is_pid(Process.get(@process_key))

  @spec set_current(UnitOfWork.t()) :: UnitOfWork.t()
  def set_current(unit_of_work) when is_pid(unit_of_work) do
    ensure_table!()
    correlation_id = UnitOfWork.correlation_id(unit_of_work)

    Process.put(@process_key, unit_of_work)
    :ets.insert(@table, {correlation_id.value, unit_of_work})
    UnitOfWork.on_completed(unit_of_work, &unit_of_work_completed/1)

    unit_of_work
  end

  @spec try_get_for(CorrelationId.t() | String.t()) :: {:ok, UnitOfWork.t()} | :error
  def try_get_for(%CorrelationId{value: value}), do: try_get_for(value)

  def try_get_for(correlation_id) when is_binary(correlation_id) do
    ensure_table!()

    case :ets.lookup(@table, correlation_id) do
      [{^correlation_id, unit_of_work}] -> {:ok, unit_of_work}
      [] -> :error
    end
  end

  defp unit_of_work_completed(unit_of_work) do
    ensure_table!()

    correlation_id = UnitOfWork.correlation_id(unit_of_work)

    if Process.get(@process_key) == unit_of_work do
      Process.delete(@process_key)
    end

    :ets.delete(@table, correlation_id.value)
    :ok
  end

  defp normalize_correlation_id(nil), do: CorrelationId.create()
  defp normalize_correlation_id(%CorrelationId{} = correlation_id), do: correlation_id
  defp normalize_correlation_id(value) when is_binary(value), do: CorrelationId.new(value)

  defp ensure_table! do
    case :ets.whereis(@table) do
      :undefined ->
        try do
          :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
        rescue
          ArgumentError -> @table
        end

      _ ->
        @table
    end
  end
end
