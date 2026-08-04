# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.ExternalServices.DefinitionBuilder do
  @moduledoc """
  Immutable, pipe-friendly builder for external service definitions.

  Mirrors the C# client's `IExternalServiceBuilder`: `http/2` configures an
  HTTP endpoint, `ms_sql/6` and `postgre_sql/6` configure a database endpoint
  (mutually exclusive with `http/2` and each other — the last call wins), and
  `with_basic_auth/3`, `with_bearer_token/2`, and `with_oauth/4` are likewise
  mutually exclusive with each other and only meaningful for HTTP endpoints.
  """

  alias Chronicle.ExternalServices.Definition

  defstruct type: :http,
            url: "",
            authorization: nil,
            headers: %{},
            host: "",
            port: 0,
            database: "",
            username: "",
            password: "",
            options: %{}

  @type t :: %__MODULE__{
          type: :http | :ms_sql | :postgre_sql,
          url: String.t(),
          authorization: Definition.authorization() | nil,
          headers: %{optional(String.t()) => String.t()},
          host: String.t(),
          port: non_neg_integer(),
          database: String.t(),
          username: String.t(),
          password: String.t(),
          options: %{optional(String.t()) => String.t()}
        }

  @doc """
  Creates a new definition builder.
  """
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc """
  Configures the service as an HTTP endpoint.
  """
  @spec http(t(), String.t()) :: t()
  def http(%__MODULE__{} = builder, url) when is_binary(url) do
    %{builder | type: :http, url: url}
  end

  @doc """
  Configures HTTP basic authentication.
  """
  @spec with_basic_auth(t(), String.t(), String.t()) :: t()
  def with_basic_auth(%__MODULE__{} = builder, username, password) do
    %{builder | authorization: {:basic, %{username: username, password: password}}}
  end

  @doc """
  Configures HTTP bearer-token authentication.
  """
  @spec with_bearer_token(t(), String.t()) :: t()
  def with_bearer_token(%__MODULE__{} = builder, token) do
    %{builder | authorization: {:bearer, %{token: token}}}
  end

  @doc """
  Configures OAuth client-credentials authentication.
  """
  @spec with_oauth(t(), String.t(), String.t(), String.t()) :: t()
  def with_oauth(%__MODULE__{} = builder, authority, client_id, client_secret) do
    %{
      builder
      | authorization:
          {:oauth, %{authority: authority, client_id: client_id, client_secret: client_secret}}
    }
  end

  @doc """
  Adds or replaces an HTTP header sent with every request.
  """
  @spec with_header(t(), String.t(), String.t()) :: t()
  def with_header(%__MODULE__{} = builder, key, value) do
    %{builder | headers: Map.put(builder.headers, key, value)}
  end

  @doc """
  Configures the service as a Microsoft SQL Server database endpoint.
  """
  @spec ms_sql(t(), String.t(), String.t(), String.t(), String.t(), non_neg_integer()) :: t()
  def ms_sql(%__MODULE__{} = builder, host, database, username, password, port \\ 0) do
    configure_database(builder, :ms_sql, host, database, username, password, port)
  end

  @doc """
  Configures the service as a PostgreSQL database endpoint.
  """
  @spec postgre_sql(t(), String.t(), String.t(), String.t(), String.t(), non_neg_integer()) ::
          t()
  def postgre_sql(%__MODULE__{} = builder, host, database, username, password, port \\ 0) do
    configure_database(builder, :postgre_sql, host, database, username, password, port)
  end

  @doc """
  Adds a provider-specific option to a database endpoint's connection configuration.
  """
  @spec with_option(t(), String.t(), String.t()) :: t()
  def with_option(%__MODULE__{} = builder, key, value) do
    %{builder | options: Map.put(builder.options, key, value)}
  end

  @doc """
  Builds an external service definition.
  """
  @spec build(t(), String.t(), String.t()) :: Definition.t()
  def build(%__MODULE__{} = builder, id, name) when is_binary(id) and is_binary(name) do
    %Definition{
      id: id,
      name: name,
      type: builder.type,
      url: builder.url,
      authorization: builder.authorization,
      headers: builder.headers,
      host: builder.host,
      port: builder.port,
      database: builder.database,
      username: builder.username,
      password: builder.password,
      options: builder.options
    }
  end

  defp configure_database(%__MODULE__{} = builder, type, host, database, username, password, port) do
    %{
      builder
      | type: type,
        host: host,
        database: database,
        username: username,
        password: password,
        port: port
    }
  end
end
