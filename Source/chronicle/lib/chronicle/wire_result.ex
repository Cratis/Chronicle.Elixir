# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.WireResult do
  @moduledoc """
  Unwraps a Chronicle gRPC command/query result envelope.

  Every Chronicle command (`CommandResult`, `CommandResult_*`) and query
  (`QueryResult_*`) response is wrapped in an envelope carrying
  `CorrelationId`, `IsAuthorized`, `ValidationResults`, and
  `ExceptionMessages`/`ExceptionStackTrace`/`AuthorizationFailureReason`
  alongside the actual payload — in a `Response` field for commands, or a
  `Data` field for queries. A bare `CommandResult` (e.g. `Redact`,
  `RegisterEventTypes`) carries no separate payload field at all.

  `unwrap/1` centralizes the `IsAuthorized`/`ExceptionMessages` check so call
  sites don't have to repeat it, and returns the unwrapped payload — or the
  envelope itself, when there is no separate payload field.
  """

  @spec unwrap(struct()) :: {:ok, term()} | {:error, term()}
  def unwrap(envelope) do
    cond do
      not Map.get(envelope, :IsAuthorized, true) ->
        {:error, {:unauthorized, Map.get(envelope, :AuthorizationFailureReason, "")}}

      Map.get(envelope, :ExceptionMessages, []) not in [nil, []] ->
        {:error, {:exception, Map.get(envelope, :ExceptionMessages, [])}}

      Map.has_key?(envelope, :Response) ->
        {:ok, Map.get(envelope, :Response)}

      Map.has_key?(envelope, :Data) ->
        {:ok, Map.get(envelope, :Data)}

      true ->
        {:ok, envelope}
    end
  end
end
