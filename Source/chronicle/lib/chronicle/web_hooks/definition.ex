# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.WebHooks.Definition do
  @moduledoc """
  Represents a webhook definition registered with Chronicle.
  """

  alias Chronicle.WebHooks.Target

  alias Cratis.Chronicle.Contracts.Observation.Webhooks.{
    BasicAuthorization,
    BearerTokenAuthorization,
    EventType,
    OAuthAuthorization,
    OneOf_BasicAuthorization_BearerTokenAuthorization_OAuthAuthorization,
    WebhookDefinition,
    WebhookTarget
  }

  defstruct id: "",
            event_sequence_id: "event-log",
            event_types: [],
            target: %Target{},
            replayable?: true,
            active?: true

  @type t :: %__MODULE__{
          id: String.t(),
          event_sequence_id: String.t(),
          event_types: [Chronicle.WebHooks.EventType.t()],
          target: Target.t(),
          replayable?: boolean(),
          active?: boolean()
        }

  @doc false
  @spec to_proto(t()) :: WebhookDefinition.t()
  def to_proto(%__MODULE__{} = definition) do
    struct(WebhookDefinition,
      EventSequenceId: definition.event_sequence_id,
      Identifier: definition.id,
      EventTypes: Enum.map(definition.event_types, &event_type_to_proto/1),
      Target: target_to_proto(definition.target),
      IsReplayable: definition.replayable?,
      IsActive: definition.active?
    )
  end

  @doc false
  @spec from_proto(map()) :: t()
  def from_proto(definition) do
    %__MODULE__{
      id: Map.get(definition, :Identifier, Map.get(definition, :identifier, "")),
      event_sequence_id:
        Map.get(
          definition,
          :EventSequenceId,
          Map.get(definition, :event_sequence_id, "event-log")
        ),
      event_types:
        definition
        |> Map.get(:EventTypes, Map.get(definition, :event_types, []))
        |> Enum.map(&event_type_from_proto/1),
      target: target_from_proto(Map.get(definition, :Target, Map.get(definition, :target))),
      replayable?: Map.get(definition, :IsReplayable, Map.get(definition, :is_replayable, true)),
      active?: Map.get(definition, :IsActive, Map.get(definition, :is_active, true))
    }
  end

  defp event_type_to_proto(%Chronicle.WebHooks.EventType{} = event_type) do
    struct(EventType,
      Id: event_type.id,
      Generation: event_type.generation,
      Tombstone: false
    )
  end

  defp event_type_from_proto(event_type) do
    %Chronicle.WebHooks.EventType{
      id: Map.get(event_type, :Id, Map.get(event_type, :id, "")),
      generation: Map.get(event_type, :Generation, Map.get(event_type, :generation, 1))
    }
  end

  defp target_to_proto(%Target{} = target) do
    struct(WebhookTarget,
      Url: target.url,
      Headers: target.headers,
      Authorization: authorization_to_proto(target.authorization)
    )
  end

  defp target_from_proto(nil), do: %Target{}

  defp target_from_proto(target) do
    %Target{
      url: Map.get(target, :Url, Map.get(target, :url, "")),
      headers: Map.get(target, :Headers, Map.get(target, :headers, %{})),
      authorization:
        authorization_from_proto(Map.get(target, :Authorization, Map.get(target, :authorization)))
    }
  end

  defp authorization_to_proto(nil), do: nil

  defp authorization_to_proto({:basic, %{username: username, password: password}}) do
    struct(OneOf_BasicAuthorization_BearerTokenAuthorization_OAuthAuthorization,
      Value0: struct(BasicAuthorization, Username: username, Password: password)
    )
  end

  defp authorization_to_proto({:bearer, %{token: token}}) do
    struct(OneOf_BasicAuthorization_BearerTokenAuthorization_OAuthAuthorization,
      Value1: struct(BearerTokenAuthorization, Token: token)
    )
  end

  defp authorization_to_proto(
         {:oauth, %{authority: authority, client_id: client_id, client_secret: client_secret}}
       ) do
    struct(OneOf_BasicAuthorization_BearerTokenAuthorization_OAuthAuthorization,
      Value2:
        struct(OAuthAuthorization,
          Authority: authority,
          ClientId: client_id,
          ClientSecret: client_secret
        )
    )
  end

  defp authorization_from_proto(nil), do: nil

  defp authorization_from_proto(authorization) do
    cond do
      basic = Map.get(authorization, :Value0, Map.get(authorization, :value0)) ->
        {:basic,
         %{
           username: Map.get(basic, :Username, Map.get(basic, :username, "")),
           password: Map.get(basic, :Password, Map.get(basic, :password, ""))
         }}

      bearer = Map.get(authorization, :Value1, Map.get(authorization, :value1)) ->
        {:bearer, %{token: Map.get(bearer, :Token, Map.get(bearer, :token, ""))}}

      oauth = Map.get(authorization, :Value2, Map.get(authorization, :value2)) ->
        {:oauth,
         %{
           authority: Map.get(oauth, :Authority, Map.get(oauth, :authority, "")),
           client_id: Map.get(oauth, :ClientId, Map.get(oauth, :client_id, "")),
           client_secret: Map.get(oauth, :ClientSecret, Map.get(oauth, :client_secret, ""))
         }}

      true ->
        nil
    end
  end
end
