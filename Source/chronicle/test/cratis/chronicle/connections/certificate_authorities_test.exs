# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Cratis.Chronicle.Connections.CertificateAuthoritiesTest do
  use ExUnit.Case, async: true

  alias Cratis.Chronicle.Connections.{CertificateAuthorities, ConnectionString}

  @moduletag :tmp_dir

  defp connection_string(path) do
    ConnectionString.parse(
      "chronicle://server:35000?caCertificatePath=#{URI.encode_www_form(path)}"
    )
  end

  defp authority_der do
    %{client_config: config} =
      :public_key.pkix_test_data(%{
        server_chain: %{root: [], peer: []},
        client_chain: %{root: [], peer: []}
      })

    [der | _] = Keyword.fetch!(config, :cacerts)
    der
  end

  test "is nil when the option is not set" do
    assert CertificateAuthorities.load!(ConnectionString.parse("chronicle://server:35000")) == nil
  end

  test "loads every certificate in the file", %{tmp_dir: dir} do
    first = authority_der()
    second = authority_der()
    path = Path.join(dir, "ca.pem")

    File.write!(
      path,
      :public_key.pem_encode([
        {:Certificate, first, :not_encrypted},
        {:Certificate, second, :not_encrypted}
      ])
    )

    assert CertificateAuthorities.load!(connection_string(path)) == [first, second]
  end

  test "raises when the file cannot be read", %{tmp_dir: dir} do
    assert_raise ArgumentError, ~r/cannot read CA certificate file/, fn ->
      CertificateAuthorities.load!(connection_string(Path.join(dir, "missing.pem")))
    end
  end

  test "raises when the file holds no certificates", %{tmp_dir: dir} do
    path = Path.join(dir, "empty.pem")
    File.write!(path, "not a certificate")

    assert_raise ArgumentError, ~r/does not contain any certificates/, fn ->
      CertificateAuthorities.load!(connection_string(path))
    end
  end
end
