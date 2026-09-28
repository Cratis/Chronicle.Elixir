# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Connections.ClientCertificate do
  @moduledoc false

  alias Chronicle.Connections.ConnectionString

  @key_types [:RSAPrivateKey, :DSAPrivateKey, :ECPrivateKey, :PrivateKeyInfo]

  @doc false
  @spec load!(ConnectionString.t()) :: keyword()
  def load!(%ConnectionString{certificate_path: nil, certificate_password: nil}), do: []
  def load!(%ConnectionString{certificate_path: ""}), do: []

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
        entries = :public_key.pem_decode(contents)
        pem = if entries == [], do: pkcs12!(path, password), else: contents
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

    case run_pkcs12(executable, path, password, []) do
      {:ok, pem} ->
        pem

      {:error, output} ->
        # OpenSSL 3 requires the legacy provider for older PKCS#12 exports.
        # Do not retry on a wrong password, and do not expose OpenSSL output
        # (which can include certificate metadata) in an exception or log.
        if String.contains?(output, ["unsupported", "Algorithm (RC2", "inner_evp_generic_fetch"]) do
          case run_pkcs12(executable, path, password, ["-legacy"]) do
            {:ok, pem} -> pem
            {:error, _} -> invalid!(path)
          end
        else
          invalid!(path)
        end
    end
  end

  defp run_pkcs12(executable, path, password, extra_args) do
    port =
      Port.open({:spawn_executable, executable}, [
        :binary,
        :exit_status,
        :use_stdio,
        :stderr_to_stdout,
        args: ["pkcs12", "-in", path, "-nodes", "-passin", "stdin"] ++ extra_args
      ])

    Port.command(port, (password || "") <> "\n")
    collect_pkcs12!(port, path, [])
  end

  defp collect_pkcs12!(port, path, output) do
    receive do
      {^port, {:data, bytes}} ->
        collect_pkcs12!(port, path, [bytes | output])

      {^port, {:exit_status, status}} ->
        bytes = output |> Enum.reverse() |> IO.iodata_to_binary()
        if status == 0, do: {:ok, bytes}, else: {:error, bytes}
    after
      10_000 ->
        Port.close(port)
        raise ArgumentError, "timed out loading client certificate #{path}"
    end
  end

  defp decode_pem!(pem, path, password) do
    entries = :public_key.pem_decode(pem)

    certificates = for {:Certificate, certificate, _} <- entries, do: certificate

    with [certificate | _] <- certificates,
         {type, key, encryption} when type in @key_types <-
           Enum.find(entries, fn {type, _, _} -> type in @key_types end),
         {:ok, key_der} <- decode_key(type, key, encryption, password) do
      Enum.each(certificates, &:public_key.pkix_decode_cert(&1, :otp))
      cert = if length(certificates) == 1, do: certificate, else: certificates
      [cert: cert, key: {type, key_der}]
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
    decoded = :public_key.pem_entry_decode({type, der, encryption}, :binary.bin_to_list(password))
    {:ok, :public_key.der_encode(type, decoded)}
  rescue
    _ -> :error
  end

  @doc false
  def server_verify_options([]), do: []

  def server_verify_options(certificate) do
    leaf = certificate[:cert]
    leaf = if is_list(leaf), do: hd(leaf), else: leaf
    pinned_hash = :crypto.hash(:sha, leaf)

    verify_fun = fn _cert, der, event, state ->
      case event do
        {:bad_cert, _} = reason ->
          if :crypto.hash(:sha, der) == pinned_hash,
            do: {:valid, true},
            else: {:fail, reason}

        :valid_peer ->
          if state == true and :crypto.hash(:sha, der) != pinned_hash,
            do: {:fail, :pinned_certificate_mismatch},
            else: {:valid, state}

        {:extension, _} ->
          {:unknown, state}

        _ ->
          {:valid, state}
      end
    end

    [verify_fun: {verify_fun, false}]
  end

  defp invalid!(path) do
    raise ArgumentError, "invalid client certificate or password for #{path}"
  end
end
