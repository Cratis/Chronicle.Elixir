# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.PayloadLimit do
  @moduledoc """
  A client-side guard for payloads the kernel would reject.

  The kernel (and gRPC) cap a single message at 4 MiB. Sending a larger one earns a
  `ResourceExhausted` error, and the failed exchange can take the shared HTTP/2 connection with
  it, silencing every observer of the client. This guard refuses such a payload *before* it is
  sent, with a precise error: `{:error, {:payload_too_large, size_in_bytes, limit_in_bytes}}`.

  The limit defaults to 4 MiB (`4_194_304` bytes) and is configurable:

      config :cratis_chronicle, max_payload_bytes: 8 * 1024 * 1024

  Set it to `:infinity` to disable the guard.
  """

  @default_limit 4_194_304

  @type error :: {:payload_too_large, non_neg_integer(), pos_integer()}

  @doc "The configured limit in bytes (or `:infinity`)."
  @spec limit() :: pos_integer() | :infinity
  def limit, do: Application.get_env(:cratis_chronicle, :max_payload_bytes, @default_limit)

  @doc "Checks a binary payload against the limit."
  @spec check(binary() | non_neg_integer()) :: :ok | {:error, error()}
  def check(payload) when is_binary(payload), do: check(byte_size(payload))

  def check(size) when is_integer(size) do
    case limit() do
      :infinity -> :ok
      limit when size > limit -> {:error, {:payload_too_large, size, limit}}
      _ -> :ok
    end
  end

  @doc "Checks the combined serialized size of a list of binaries."
  @spec check_all([binary()]) :: :ok | {:error, error()}
  def check_all(payloads) do
    payloads |> Enum.reduce(0, &(byte_size(&1) + &2)) |> check()
  end
end
