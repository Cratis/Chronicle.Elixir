# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Seeding.KernelRequestTest do
  use ExUnit.Case, async: true

  alias Chronicle.Seeding

  defmodule Opened do
    use Chronicle.Events.EventType, id: "seed-opened", tags: ["seed"]
    defstruct owner_name: ""
  end

  defmodule Deposited do
    use Chronicle.Events.EventType, id: "seed-deposited"
    defstruct amount: 0
  end

  defp builder(extra \\ []) do
    struct(
      %Seeding{event_store: "store", namespace: "Default", client: :test_client},
      extra
    )
  end

  defp f(map, key), do: Map.fetch!(map, key)

  test "global entries are grouped by event type and by event source, with camelCase content and tags" do
    request =
      builder()
      |> Seeding.for(Opened, "a1", [%Opened{owner_name: "Ada"}])
      |> Seeding.for_event_source("a1", [%Deposited{amount: 5}])
      |> Seeding.build_seed_request()

    assert f(request, :EventStore) == "store"
    assert f(request, :NamespacedEntries) == []

    types = request |> f(:GlobalByEventType) |> Map.new(&{f(&1, :EventTypeId), &1})
    assert Map.keys(types) |> Enum.sort() == ["seed-deposited", "seed-opened"]

    [entry] = f(types["seed-opened"], :Entries)
    assert Jason.decode!(f(entry, :Content)) == %{"ownerName" => "Ada"}
    assert f(entry, :Tags) == ["seed"]

    [source] = f(request, :GlobalByEventSource)
    assert f(source, :EventSourceId) == "a1"
    assert length(f(source, :Entries)) == 2
  end

  test "namespaced entries are grouped per namespace and are not global" do
    request =
      builder()
      |> Seeding.for_namespace("tenant-1", fn scoped ->
        Seeding.for(scoped, Deposited, "a2", [%Deposited{amount: 1}])
      end)
      |> Seeding.build_seed_request()

    assert f(request, :GlobalByEventType) == []
    assert [namespaced] = f(request, :NamespacedEntries)
    assert f(namespaced, :Namespace) == "tenant-1"
    assert [%{} = by_source] = f(namespaced, :ByEventSource)
    assert f(by_source, :EventSourceId) == "a2"
  end

  test "register hands the request to the kernel path instead of appending" do
    test = self()

    result =
      builder(seed_events: fn request -> send(test, {:request, request}) && :ok end)
      |> Seeding.for(Opened, "a1", [%Opened{owner_name: "Ada"}])
      |> Seeding.register()

    assert result == :ok
    assert_received {:request, request}
    assert [_] = f(request, :GlobalByEventType)
  end

  test "register with nothing to seed does not call the kernel" do
    assert Seeding.register(builder(seed_events: fn _ -> flunk("called") end)) == :ok
  end

  test "a kernel failure is returned so the runner retries" do
    assert builder(seed_events: fn _ -> {:error, :down} end)
           |> Seeding.for(Opened, "a1", [%Opened{}])
           |> Seeding.register() == {:error, :down}
  end
end
