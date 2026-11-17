# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Connections.CertificateAuthorities do
  @moduledoc false

  # Loads the certificate authorities named by the connection string's `caCertificatePath`.
  #
  # The file holds one or more PEM encoded CA certificates. They replace the system trust store
  # when certificate validation is on (`skipTlsValidation=false`). Like the .NET client, the file
  # is read whenever the option is set - also when validation is skipped or TLS is disabled - so
  # a missing or unreadable file, or one without certificates, fails the connection setup instead
  # of lying dormant until validation is switched on.

  alias Chronicle.Connections.ConnectionString

  @doc false
  @spec load!(ConnectionString.t()) :: [binary()] | nil
  def load!(%ConnectionString{ca_certificate_path: path}) when path in [nil, ""], do: nil

  def load!(%ConnectionString{ca_certificate_path: path}) do
    contents =
      case File.read(path) do
        {:ok, contents} -> contents
        {:error, _reason} -> raise ArgumentError, "cannot read CA certificate file #{path}"
      end

    case for({:Certificate, der, :not_encrypted} <- decode!(contents, path), do: der) do
      [] -> raise ArgumentError, "CA certificate file #{path} does not contain any certificates"
      certificates -> certificates
    end
  end

  defp decode!(contents, path) do
    :public_key.pem_decode(contents)
  rescue
    _error -> raise ArgumentError, "CA certificate file #{path} is not valid PEM"
  end
end
