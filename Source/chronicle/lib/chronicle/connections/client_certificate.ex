# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Connections.ClientCertificate do
  @moduledoc false

  alias Chronicle.Connections.{ConnectionString, PrivateKeySigner}

  require Record

  Record.defrecordp(
    :otp_cert,
    Record.extract(:OTPCertificate, from_lib: "public_key/include/public_key.hrl")
  )

  Record.defrecordp(
    :otp_tbs,
    Record.extract(:OTPTBSCertificate, from_lib: "public_key/include/public_key.hrl")
  )

  Record.defrecordp(
    :otp_spki,
    Record.extract(:OTPSubjectPublicKeyInfo, from_lib: "public_key/include/public_key.hrl")
  )

  Record.defrecordp(
    :otp_algorithm,
    Record.extract(:PublicKeyAlgorithm, from_lib: "public_key/include/public_key.hrl")
  )

  Record.defrecordp(
    :dsa_key,
    Record.extract(:DSAPrivateKey, from_lib: "public_key/include/public_key.hrl")
  )

  Record.defrecordp(
    :dsa_params,
    Record.extract(:"Dss-Parms", from_lib: "public_key/include/public_key.hrl")
  )

  @key_types [:RSAPrivateKey, :DSAPrivateKey, :ECPrivateKey, :PrivateKeyInfo]
  @doc false
  @spec load!(ConnectionString.t()) :: keyword()
  def load!(%ConnectionString{certificate_path: nil, certificate_password: password})
      when password in [nil, ""], do: []

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
        entries = safe_pem_decode!(contents, path)
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

  defp safe_pem_decode!(contents, path) do
    :public_key.pem_decode(contents)
  rescue
    # A malformed PEM can put its Base64 key in :pubkey_pem stack arguments.
    # Raise a fresh error at this boundary, without the parser's reason/stack.
    _ -> invalid!(path)
  end

  defp decode_pem!(pem, path, password) do
    entries = safe_pem_decode!(pem, path)

    certificates = for {:Certificate, certificate, _} <- entries, do: certificate

    with [_ | _] <- certificates,
         {type, key, encryption} when type in @key_types <-
           Enum.find(entries, fn {type, _, _} -> type in @key_types end),
         {:ok, key_der} <- decode_key(type, key, encryption, password),
         private_key <- :public_key.pem_entry_decode({type, key_der, :not_encrypted}),
         certificate when is_binary(certificate) <-
           Enum.find(certificates, &owns_key?(&1, private_key)) do
      certs = [certificate | List.delete(certificates, certificate)]
      cert = if length(certs) == 1, do: certificate, else: certs
      # The decrypted DER must not enter a channel, token provider or TLS
      # process: all three can appear in dependency crash reports.
      algorithm = signing_algorithm(certificate)
      [cert: cert, key: PrivateKeySigner.start(private_key, algorithm)]
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

  defp owns_key?(certificate, private_key) do
    # Verify key ownership, independent of bundle order. For RSA/EC sign a
    # challenge; for DSA derive the public key (PKCS#8 may omit its y field).
    cert = :public_key.pkix_decode_cert(certificate, :otp)
    spki = cert |> otp_cert(:tbsCertificate) |> otp_tbs(:subjectPublicKeyInfo)
    public_key = otp_spki(spki, :subjectPublicKey)
    parameters = spki |> otp_spki(:algorithm) |> otp_algorithm(:parameters)

    algorithm = spki |> otp_spki(:algorithm) |> otp_algorithm(:algorithm)

    verifier_key =
      cond do
        is_tuple(public_key) and elem(public_key, 0) == :RSAPublicKey ->
          public_key

        algorithm in [{1, 3, 101, 112}, {1, 3, 101, 113}] ->
          {public_key, {:namedCurve, algorithm}}

        true ->
          {public_key, parameters}
      end

    if elem(private_key, 0) == :DSAPrivateKey do
      {:params, dss} = parameters

      derived =
        :crypto.mod_pow(
          dsa_key(private_key, :g),
          dsa_key(private_key, :x),
          dsa_key(private_key, :p)
        )

      public_key == :binary.decode_unsigned(derived) and
        dsa_params(dss, :p) == dsa_key(private_key, :p) and
        dsa_params(dss, :q) == dsa_key(private_key, :q) and
        dsa_params(dss, :g) == dsa_key(private_key, :g)
    else
      challenge = "Chronicle client certificate identity"
      digest = if algorithm in [{1, 3, 101, 112}, {1, 3, 101, 113}], do: :none, else: :sha256
      signature = :public_key.sign(challenge, digest, private_key)
      :public_key.verify(challenge, digest, signature, verifier_key)
    end
  rescue
    _ -> false
  end

  defp signing_algorithm(certificate) do
    certificate
    |> :public_key.pkix_decode_cert(:otp)
    |> otp_cert(:tbsCertificate)
    |> otp_tbs(:subjectPublicKeyInfo)
    |> otp_spki(:algorithm)
    |> otp_algorithm(:algorithm)
    |> case do
      {1, 2, 840, 113_549, 1, 1, _} -> :rsa
      {1, 2, 840, 10045, 2, 1} -> :ecdsa
      {1, 3, 101, curve} when curve in [112, 113] -> :eddsa
      {1, 2, 840, 10040, 4, 1} -> :dsa
    end
  end

  defp invalid!(path) do
    raise ArgumentError, "invalid client certificate or password for #{path}"
  end
end
