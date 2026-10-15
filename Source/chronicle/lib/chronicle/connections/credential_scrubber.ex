# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Connections.CredentialScrubber do
  @moduledoc false

  # Removes credentials from terms and text that are about to be logged. Two things are
  # recognized, both without ever inspecting or printing a secret:
  #
  #   * structure: the dependency states that hold request headers (the gRPC stream, the
  #     connection and channel, Mint's HTTP/2 connection with its HPACK tables) and any
  #     header pair or map entry named like a credential header;
  #   * value: the credentials this node currently authenticates with, remembered by
  #     `Chronicle.Connections.CredentialRegistry`, wherever they occur in text.
  #
  # Only the secret-bearing parts are replaced, so the process, the reason and the
  # stacktrace frames of a crash report stay readable.

  alias Chronicle.Connections.CredentialRegistry

  @redacted :"[redacted]"
  @redacted_text "[redacted]"

  # State that holds request headers, or a copy of them, in a form that cannot be scrubbed
  # field by field. Named by atom so the Mint adapter modules need not be compiled in.
  @header_bearing [
    GRPC.Client.Stream,
    GRPC.Client.Connection,
    GRPC.Client.Adapters.Mint.ConnectionProcess.State,
    Mint.HTTP2,
    HPAX.Table
  ]

  @sensitive_headers ["api-key", "authorization", "proxy-authorization"]
  @text_markers ["Bearer ", "bearer ", "api-key", "authorization", "Authorization"]

  @bearer ~r/\bbearer\s+[A-Za-z0-9._~+\/=-]+/i
  @header_text ~r/(\\?"(?:api-key|authorization|proxy-authorization)\\?"\s*(?:,|=>)\s*\\?")[^"\\]*/i

  @doc "Scrubs any term. Returns the term unchanged when it holds nothing to remove."
  @spec term(term()) :: term()
  def term(%{__struct__: module} = struct) when module in @header_bearing, do: placeholder(struct)

  def term(%GRPC.Channel{headers: headers} = channel) when headers not in [nil, []],
    do: channel |> Map.put(:headers, @redacted) |> map()

  def term(%{__struct__: _} = struct), do: map(struct)
  def term(map) when is_map(map), do: map(map)
  def term([]), do: []
  def term([_ | _] = list), do: list(list)
  def term(binary) when is_binary(binary), do: text(binary)

  def term({name, value} = pair) when is_binary(name) do
    if sensitive_header?(name), do: {name, redact(value)}, else: tuple(pair)
  end

  def term(tuple) when is_tuple(tuple), do: tuple(tuple)
  def term(other), do: other

  @doc "Scrubs text, replacing remembered credentials and credential header values."
  @spec text(binary()) :: binary()
  def text(binary) do
    secrets = CredentialRegistry.values()

    case :binary.match(binary, secrets ++ @text_markers) do
      :nomatch -> binary
      _ -> scrub_text(binary, secrets)
    end
  end

  @doc "Scrubs chardata such as a Logger string message."
  @spec chardata(IO.chardata()) :: IO.chardata()
  def chardata(data) when is_binary(data), do: text(data)

  def chardata(data) do
    string = IO.chardata_to_string(data)
    scrubbed = text(string)
    if scrubbed == string, do: data, else: scrubbed
  rescue
    _ -> term(data)
  end

  defp scrub_text(binary, secrets) do
    binary
    |> replace_secrets(secrets)
    |> then(&Regex.replace(@bearer, &1, "Bearer " <> @redacted_text))
    |> then(&Regex.replace(@header_text, &1, "\\1" <> @redacted_text))
  end

  defp replace_secrets(binary, []), do: binary

  defp replace_secrets(binary, secrets),
    do: :binary.replace(binary, secrets, @redacted_text, [:global])

  defp placeholder(%{__struct__: module}),
    do: :"[redacted: #{inspect(module)} holds request headers]"

  defp redact(value) when is_binary(value), do: @redacted_text
  defp redact(_value), do: @redacted

  defp sensitive_header?(name), do: String.downcase(name) in @sensitive_headers

  defp map(map) do
    map
    |> :maps.to_list()
    |> Map.new(fn
      {:__struct__, module} ->
        {:__struct__, module}

      {key, value} when is_binary(key) ->
        if sensitive_header?(key), do: {key, redact(value)}, else: {key, term(value)}

      {key, value} ->
        {term(key), term(value)}
    end)
  end

  defp tuple(tuple), do: tuple |> Tuple.to_list() |> Enum.map(&term/1) |> List.to_tuple()

  # Stacktraces and iodata can be improper lists.
  defp list([head | tail]) when is_list(tail), do: [term(head) | list(tail)]
  defp list([head | tail]), do: [term(head) | term(tail)]
  defp list([]), do: []
end
