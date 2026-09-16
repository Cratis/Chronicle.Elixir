# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.EventSequences.AppendResponse do
  @moduledoc false

  @spec normalize(term()) :: :ok | {:error, term()}
  def normalize(response) when is_map(response) do
    constraints = field(response, :ConstraintViolations, :constraint_violations, [])
    errors = field(response, :Errors, :errors, [])

    concurrency = field(response, :ConcurrencyViolations, :concurrency_violations, [])
    single_violation = field(response, :ConcurrencyViolation, :concurrency_violation, nil)

    if is_list(constraints) and is_list(errors) and is_list(concurrency) do
      normalize_checked(response, constraints, errors, concurrency ++ List.wrap(single_violation))
    else
      {:error, {:invalid_append_response, response}}
    end
  end

  def normalize(response), do: {:error, {:invalid_append_response, response}}

  defp normalize_checked(response, constraints, errors, concurrency) do
    cond do
      constraints != [] ->
        {:error, {:constraint_violations, constraints}}

      concurrency != [] ->
        {:error, {:concurrency_violations, concurrency}}

      errors != [] ->
        {:error, {:append_errors, errors}}

      field(response, :HasConstraintViolations, :has_constraint_violations, false) != false ->
        {:error, {:constraint_violations, []}}

      field(response, :HasConcurrencyViolations, :has_concurrency_violations, false) != false ->
        {:error, {:concurrency_violations, []}}

      field(response, :HasErrors, :has_errors, false) != false ->
        {:error, {:append_errors, []}}

      field(response, :IsSuccess, :is_success, false) == true ->
        :ok

      true ->
        {:error, {:append_rejected, response}}
    end
  end

  defp field(response, wire_name, name, default),
    do: Map.get(response, wire_name, Map.get(response, name, default))
end
