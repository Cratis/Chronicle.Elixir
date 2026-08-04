# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.ExternalServicesTest do
  use ExUnit.Case, async: true

  alias Chronicle.ExternalServices.{Definition, DefinitionBuilder}

  describe "DefinitionBuilder" do
    test "http/2 configures an HTTP endpoint" do
      definition =
        DefinitionBuilder.new()
        |> DefinitionBuilder.http("https://example.com")
        |> DefinitionBuilder.build("svc", "svc")

      assert definition.id == "svc"
      assert definition.name == "svc"
      assert definition.type == :http
      assert definition.url == "https://example.com"
      assert definition.authorization == nil
    end

    test "auth methods are mutually exclusive, last call wins" do
      definition =
        DefinitionBuilder.new()
        |> DefinitionBuilder.http("https://example.com")
        |> DefinitionBuilder.with_basic_auth("user", "pass")
        |> DefinitionBuilder.with_bearer_token("token")
        |> DefinitionBuilder.with_oauth("https://authority", "client-id", "client-secret")
        |> DefinitionBuilder.build("svc", "svc")

      assert definition.authorization ==
               {:oauth,
                %{
                  authority: "https://authority",
                  client_id: "client-id",
                  client_secret: "client-secret"
                }}
    end

    test "with_header/3 accumulates headers, last write wins per key" do
      definition =
        DefinitionBuilder.new()
        |> DefinitionBuilder.http("https://example.com")
        |> DefinitionBuilder.with_header("x-a", "1")
        |> DefinitionBuilder.with_header("x-b", "2")
        |> DefinitionBuilder.with_header("x-a", "3")
        |> DefinitionBuilder.build("svc", "svc")

      assert definition.headers == %{"x-a" => "3", "x-b" => "2"}
    end

    test "ms_sql/6 configures a database endpoint, mutually exclusive with http" do
      definition =
        DefinitionBuilder.new()
        |> DefinitionBuilder.http("https://example.com")
        |> DefinitionBuilder.ms_sql("db-host", "my-db", "user", "pass", 1433)
        |> DefinitionBuilder.build("svc", "svc")

      assert definition.type == :ms_sql
      assert definition.host == "db-host"
      assert definition.database == "my-db"
      assert definition.username == "user"
      assert definition.password == "pass"
      assert definition.port == 1433
    end

    test "postgre_sql/6 defaults port to 0" do
      definition =
        DefinitionBuilder.new()
        |> DefinitionBuilder.postgre_sql("db-host", "my-db", "user", "pass")
        |> DefinitionBuilder.build("svc", "svc")

      assert definition.type == :postgre_sql
      assert definition.port == 0
    end

    test "postgre_sql/6 after ms_sql/6 wins, mutually exclusive" do
      definition =
        DefinitionBuilder.new()
        |> DefinitionBuilder.ms_sql("mssql-host", "mssql-db", "u1", "p1", 1433)
        |> DefinitionBuilder.postgre_sql("pg-host", "pg-db", "u2", "p2", 5432)
        |> DefinitionBuilder.build("svc", "svc")

      assert definition.type == :postgre_sql
      assert definition.host == "pg-host"
      assert definition.database == "pg-db"
    end

    test "with_option/3 accumulates provider-specific connection options" do
      definition =
        DefinitionBuilder.new()
        |> DefinitionBuilder.ms_sql("db-host", "my-db", "user", "pass")
        |> DefinitionBuilder.with_option("Encrypt", "true")
        |> DefinitionBuilder.with_option("TrustServerCertificate", "true")
        |> DefinitionBuilder.build("svc", "svc")

      assert definition.options == %{"Encrypt" => "true", "TrustServerCertificate" => "true"}
    end
  end

  describe "Definition.to_proto/1" do
    test "converts an HTTP definition with bearer auth" do
      proto =
        DefinitionBuilder.new()
        |> DefinitionBuilder.http("https://example.com")
        |> DefinitionBuilder.with_bearer_token("token")
        |> DefinitionBuilder.with_header("x-source", "chronicle-elixir")
        |> DefinitionBuilder.build("svc", "svc")
        |> Definition.to_proto()

      assert Map.get(proto, :Id) == "svc"
      assert Map.get(proto, :Name) == "svc"
      endpoint = Map.get(proto, :Endpoint)
      assert Map.get(endpoint, :Type) == :Http
      http = Map.get(endpoint, :Http)
      assert Map.get(http, :Url) == "https://example.com"
      assert Map.get(http, :Headers) == %{"x-source" => "chronicle-elixir"}
      authorization = Map.get(http, :Authorization)
      assert Map.get(Map.get(authorization, :Value1), :Token) == "token"
      assert Map.get(endpoint, :Database) == nil
    end

    test "converts a database definition" do
      proto =
        DefinitionBuilder.new()
        |> DefinitionBuilder.postgre_sql("db-host", "my-db", "user", "pass", 5432)
        |> DefinitionBuilder.with_option("sslmode", "require")
        |> DefinitionBuilder.build("svc", "svc")
        |> Definition.to_proto()

      endpoint = Map.get(proto, :Endpoint)
      assert Map.get(endpoint, :Type) == :PostgreSql
      assert Map.get(endpoint, :Http) == nil
      database = Map.get(endpoint, :Database)
      assert Map.get(database, :Host) == "db-host"
      assert Map.get(database, :Database) == "my-db"
      assert Map.get(database, :Options) == %{"sslmode" => "require"}
    end
  end
end
