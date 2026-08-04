# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.ExternalServices.Definition do
  @moduledoc """
  Represents an external service definition registered with Chronicle.
  """

  alias Cratis.Chronicle.Contracts.ExternalServices.{
    BasicAuthorization,
    BearerTokenAuthorization,
    DatabaseEndpointConfiguration,
    ExternalServiceDefinition,
    ExternalServiceEndpoint,
    HttpEndpointConfiguration,
    OAuthAuthorization,
    OneOf_BasicAuthorization_BearerTokenAuthorization_OAuthAuthorization
  }

  defstruct id: "",
            name: "",
            type: :http,
            url: "",
            authorization: nil,
            headers: %{},
            host: "",
            port: 0,
            database: "",
            username: "",
            password: "",
            options: %{}

  @type authorization ::
          {:basic, %{username: String.t(), password: String.t()}}
          | {:bearer, %{token: String.t()}}
          | {:oauth, %{authority: String.t(), client_id: String.t(), client_secret: String.t()}}

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          type: :http | :ms_sql | :postgre_sql,
          url: String.t(),
          authorization: authorization() | nil,
          headers: %{optional(String.t()) => String.t()},
          host: String.t(),
          port: non_neg_integer(),
          database: String.t(),
          username: String.t(),
          password: String.t(),
          options: %{optional(String.t()) => String.t()}
        }

  @doc false
  @spec to_proto(t()) :: ExternalServiceDefinition.t()
  def to_proto(%__MODULE__{} = definition) do
    struct(ExternalServiceDefinition,
      Id: definition.id,
      Name: definition.name,
      Endpoint: endpoint_to_proto(definition)
    )
  end

  defp endpoint_to_proto(%__MODULE__{type: :http} = definition) do
    struct(ExternalServiceEndpoint,
      Type: :Http,
      Http:
        struct(HttpEndpointConfiguration,
          Url: definition.url,
          Authorization: authorization_to_proto(definition.authorization),
          Headers: definition.headers
        )
    )
  end

  defp endpoint_to_proto(%__MODULE__{type: type} = definition) do
    struct(ExternalServiceEndpoint,
      Type: database_type_to_proto(type),
      Database:
        struct(DatabaseEndpointConfiguration,
          Host: definition.host,
          Port: definition.port,
          Database: definition.database,
          Username: definition.username,
          Password: definition.password,
          Options: definition.options
        )
    )
  end

  defp database_type_to_proto(:ms_sql), do: :MsSql
  defp database_type_to_proto(:postgre_sql), do: :PostgreSql

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
end
