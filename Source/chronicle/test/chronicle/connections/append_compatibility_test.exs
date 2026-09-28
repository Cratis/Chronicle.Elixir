# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Connections.AppendCompatibilityTest do
  use Chronicle.AppendWireCase, async: false

  alias Cratis.Chronicle.Contracts.Clients.{CompatibilityRequest, CompatibilityResponse}
  alias Cratis.Chronicle.Contracts.DescriptorSet

  test "the announced protocol version is the installed contracts version" do
    version = DescriptorSet.protocol_version()
    assert version =~ ~r/^\d+\.\d+\.\d+$/
    assert Chronicle.Connections.AppendCompatibility.protocol_version() == version

    contracts_path = Mix.Project.deps_paths()[:cratis_chronicle_contracts]
    metadata_path = Path.join(contracts_path, "hex_metadata.config")

    if File.regular?(metadata_path) do
      assert {:ok, metadata} = :file.consult(metadata_path)
      assert {"version", version} = List.keyfind(metadata, "version", 0)

      {:hex, :cratis_chronicle_contracts, pinned_version, _, _, _, _, _} =
        Mix.Dep.Lock.read()[:cratis_chronicle_contracts]

      assert version == pinned_version
    else
      assert version == contracts_path |> Path.join("VERSION") |> File.read!() |> String.trim()
    end
  end

  for path <- [:single, :ordinary, :rich, :transaction] do
    test "#{path} sends the installed descriptor before append", %{opts: opts} do
      assert :ok = append(unquote(path), opts)
      assert_receive {:wire_request, %CompatibilityRequest{} = request}
      assert request."ClientType" == "Elixir"
      assert request."ProtocolVersion" == DescriptorSet.protocol_version()
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
