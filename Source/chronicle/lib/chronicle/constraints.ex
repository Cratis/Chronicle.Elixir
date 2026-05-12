# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Constraints do
  @moduledoc """
  Registers event constraints with a Chronicle event store.

  Constraints enforce invariants on the event log. The most common constraint
  is a **unique constraint** — ensuring that no two events of the same type
  share the same property value within the same event store.

  ## Registering a unique constraint

      alias Chronicle.Constraints

      {:ok, channel} = Chronicle.Connections.Connection.channel(:my_conn)
      Constraints.register(channel, "my-store", [
        %{
          name: "unique-email",
          type: :unique,
          event_type_id: "user-registered-v1",
          on: ["Email"]
        }
      ])

  Constraints are typically registered as part of event type registration
  during client startup via `Chronicle.Client`.
  """

  alias Cratis.Chronicle.Contracts.Events.Constraints.{
    Constraints,
    RegisterConstraintsRequest,
    Constraint,
    UniqueConstraintDefinition,
    UniqueConstraintEventDefinition,
    OneOf_UniqueConstraintDefinition_UniqueEventTypeConstraintDefinition
  }

  @doc """
  Registers a list of constraint definitions with Chronicle.

  Each constraint map supports:

    * `:name` — **(required)** a unique constraint name
    * `:type` — **(required)** `:unique` or `:unique_event_type`
    * `:event_type_id` — the event type ID string this constraint applies to
    * `:on` — list of property path strings to check for uniqueness

  Returns `:ok` or `{:error, reason}`.
  """
  @spec register(term(), String.t(), [map()]) :: :ok | {:error, term()}
  def register(_channel, _event_store, []), do: :ok

  def register(channel, event_store, constraints) when is_list(constraints) do
    definitions =
      Enum.map(constraints, &build_constraint/1)

    request =
      struct(RegisterConstraintsRequest,
        EventStore: event_store,
        Constraints: definitions
      )

    case Constraints.Stub.register(channel, request) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_constraint(%{
         type: :unique,
         name: name,
         event_type_id: event_type_id,
         on: properties
       }) do
    struct(Constraint,
      Name: name,
      Type: :Unique,
      Definition:
        struct(OneOf_UniqueConstraintDefinition_UniqueEventTypeConstraintDefinition,
          Value0:
            struct(UniqueConstraintDefinition,
              EventDefinitions: [
                struct(UniqueConstraintEventDefinition,
                  EventTypeId: event_type_id,
                  Properties: List.wrap(properties)
                )
              ],
              IgnoreCasing: false
            )
        )
    )
  end

  defp build_constraint(%{type: :unique, name: name, event_type: event_module} = constraint) do
    properties = Map.get(constraint, :on, [])
    event_type_id = event_module.__chronicle_event_type__(:id)

    build_constraint(%{
      constraint
      | type: :unique,
        event_type_id: event_type_id,
        on: properties,
        name: name
    })
  end
end
