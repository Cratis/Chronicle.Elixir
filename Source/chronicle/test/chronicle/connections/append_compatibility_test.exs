# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Connections.AppendCompatibilityTest do
  use Chronicle.AppendWireCase, async: false

  alias Cratis.Chronicle.Contracts.Clients.{CompatibilityRequest, CompatibilityResponse}
  alias Cratis.Chronicle.Contracts.DescriptorSet

  # The preflight must announce the contracts version this client is actually
  # built against. The package self-reports "0.1.0" at runtime (its mix.exs
  # reads a build-time env var downstream consumers never set), so the module
  # carries a hand-written constant and mix.lock holds the real resolved
  # version. Reading the lock here rather than repeating the literal is what
  # catches the two drifting apart when the pin moves.
  @lock_path Path.expand("../../../mix.lock", __DIR__)
  @external_resource @lock_path
  @pinned_contracts_version (case Map.fetch(Mix.Dep.Lock.read(), :cratis_chronicle_contracts) do
                               {:ok, entry} when is_tuple(entry) and tuple_size(entry) > 2 ->
                                 elem(entry, 2)

                               _ ->
                                 raise "cratis_chronicle_contracts is not pinned in #{@lock_path}"
                             end)

  test "the announced protocol version is the pinned contracts version" do
    assert @pinned_contracts_version =~ ~r/^\d+\.\d+\.\d+/

    assert Chronicle.Connections.AppendCompatibility.protocol_version() ==
             @pinned_contracts_version
  end

  for path <- [:single, :ordinary, :rich, :transaction] do
    test "#{path} sends the installed descriptor before append", %{opts: opts} do
      assert :ok = append(unquote(path), opts)
      assert_receive {:wire_request, %CompatibilityRequest{} = request}
      assert request."ClientType" == "Elixir"
      assert request."ProtocolVersion" == @pinned_contracts_version
      assert request."DescriptorSet" == DescriptorSet.bytes()
      assert byte_size(request."DescriptorSet") > 0
      assert request."ClientVersion" != ""
      assert_receive {:wire_request, _append_request}
    end

    test "#{path} stops before append on incompatible descriptor", %{opts: opts} do
      put_response(:compatibility_response, %CompatibilityResponse{
        IsCompatible: false,
        Incompatibilities: ["missing field"]
      })

      assert {:error, {:incompatible_server, _}} = append(unquote(path), opts)
      assert_receive {:wire_request, %CompatibilityRequest{}}
      refute_received {:wire_request, _}
    end

    test "#{path} stops before append if compatibility cannot be checked", %{opts: opts} do
      put_response(:compatibility_response, {:error, :unavailable})
      assert {:error, {:compatibility_check_failed, :unavailable}} = append(unquote(path), opts)
      assert_receive {:wire_request, %CompatibilityRequest{}}
      refute_received {:wire_request, _}
    end
  end

  test "successful verdict is shared by concurrent callers and append paths", %{opts: opts} do
    results =
      [:single, :ordinary, :rich, :transaction]
      |> Task.async_stream(&append(&1, opts))
      |> Enum.to_list()

    assert results == List.duplicate({:ok, :ok}, 4)
    assert_receive {:wire_request, %CompatibilityRequest{}}
    refute_received {:wire_request, %CompatibilityRequest{}}
    for _ <- 1..4, do: assert_receive({:wire_request, _append_request})
  end

  test "transient failure is retried on the same channel", %{opts: opts} do
    put_response(:compatibility_response, {:error, :unavailable})
    assert {:error, {:compatibility_check_failed, :unavailable}} = append(:single, opts)
    assert_receive {:wire_request, %CompatibilityRequest{}}
    refute_received {:wire_request, _}

    put_response(:compatibility_response, %CompatibilityResponse{IsCompatible: true})
    assert :ok = append(:ordinary, opts)
    assert_receive {:wire_request, %CompatibilityRequest{}}
    assert_receive {:wire_request, %Wire.AppendManyForEventSourcesRequest{}}
  end

  test "reconnect discards the successful verdict", %{opts: opts, connection: connection} do
    assert :ok = append(:single, opts)
    assert_receive {:wire_request, %CompatibilityRequest{}}
    assert_receive {:wire_request, %Wire.AppendRequest{}}

    put_response(:compatibility_response, %CompatibilityResponse{IsCompatible: false})
    :ok = Chronicle.Connections.Connection.reconnect(connection)
    :ok = Chronicle.Connections.Connection.connect(connection)

    assert {:error, {:incompatible_server, _}} = append(:ordinary, opts)
    assert_receive {:wire_request, %CompatibilityRequest{}}
    refute_received {:wire_request, _}
  end

  test "inconsistent compatibility success with reported incompatibilities is rejected", %{
    opts: opts
  } do
    put_response(:compatibility_response, %CompatibilityResponse{
      IsCompatible: true,
      Incompatibilities: ["missing field"]
    })

    assert {:error, {:incompatible_server, _}} = append(:single, opts)
    assert_receive {:wire_request, %CompatibilityRequest{}}
    refute_received {:wire_request, _}
  end
end
