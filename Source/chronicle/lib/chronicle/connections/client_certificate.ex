# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Connections.ClientCertificate do
  @moduledoc false

  alias Chronicle.Connections.ConnectionString

  @key_types [:RSAPrivateKey, :DSAPrivateKey, :ECPrivateKey, :PrivateKeyInfo]

  @doc false
  @spec load!(ConnectionString.t()) :: keyword()
  def load!(%ConnectionString{certificate_path: nil, certificate_password: nil}), do: []

  def load!(%ConnectionString{certificate_path: path, disable_tls: true}) when is_binary(path) do
    raise ArgumentError, "client certificate #{path} cannot be used when TLS is disabled"
  end

  def load!(%ConnectionString{certificate_path: path, certificate_password: password})
      when is_binary(path) and path != "" do
    if is_binary(password) and String.contains?(password, ["\n", "\r"]) do
      raise ArgumentError, "client certificate password cannot contain a newline"
    end

    case File.read(path) do
      {:ok, contents} ->
        pem =
          if String.starts_with?(contents, "-----BEGIN"),
            do: contents,
            else: pkcs12!(path, password)

        decode_pem!(pem, path, password)

      {:error, _reason} ->
        raise ArgumentError, "cannot read client certificate #{path}"
    end
  end

  def load!(%ConnectionString{certificate_path: path, certificate_password: password}) do
    if is_binary(password) do
      raise ArgumentError, "certificatePassword requires a certificatePath"
    end

    raise ArgumentError, "invalid client certificate path: #{inspect(path)}"
  end

  defp pkcs12!(path, password) do
    executable =
      System.find_executable("openssl") ||
        raise(ArgumentError, "OpenSSL is required to load client certificate #{path}")

    port =
      Port.open({:spawn_executable, executable}, [
        :binary,
        :exit_status,
        :use_stdio,
        :stderr_to_stdout,
        args: ["pkcs12", "-in", path, "-clcerts", "-nodes", "-passin", "stdin"]
      ])

    Port.command(port, (password || "") <> "\n")
    collect_pkcs12!(port, path, [])
  end

  defp collect_pkcs12!(port, path, output) do
    receive do
      {^port, {:data, bytes}} -> collect_pkcs12!(port, path, [bytes | output])
      {^port, {:exit_status, 0}} -> output |> Enum.reverse() |> IO.iodata_to_binary()
      {^port, {:exit_status, _}} -> invalid!(path)
    after
      10_000 ->
        Port.close(port)
        raise ArgumentError, "timed out loading client certificate #{path}"
    end
  end

  defp decode_pem!(pem, path, password) do
    entries = :public_key.pem_decode(pem)

    with {:Certificate, certificate, _} <- Enum.find(entries, &match?({:Certificate, _, _}, &1)),
         {type, key, encryption} when type in @key_types <-
           Enum.find(entries, fn {type, _, _} -> type in @key_types end),
         {:ok, key_der} <- decode_key(type, key, encryption, password) do
      :public_key.pkix_decode_cert(certificate, :otp)
      [cert: certificate, key: {type, key_der}]
    else
      _ -> invalid!(path)
    end
  rescue
    _ -> invalid!(path)
  end

  defp decode_key(type, der, :not_encrypted, _password) do
    :public_key.pem_entry_decode({type, der, :not_encrypted})
    {:ok, der}
  end

  defp decode_key(_type, _der, _encryption, nil), do: :error

  defp decode_key(type, der, encryption, password) do
    decoded = :public_key.pem_entry_decode({type, der, encryption}, String.to_charlist(password))
    {:ok, :public_key.der_encode(type, decoded)}
  rescue
    _ -> :error
  end

  defp invalid!(path) do
    raise ArgumentError, "invalid client certificate or password for #{path}"
  end
end
