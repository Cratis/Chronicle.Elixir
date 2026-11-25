# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Cratis.Chronicle.ReadModels.QueryPagingTest do
  @moduledoc """
  The kernel skips `page * page_size` instances, so pages count from 0. The client used to default to
  page 1 and reject 0, which made the first page unreachable.
  """
  use Cratis.Chronicle.AppendWireCase, async: false

  alias Cratis.Chronicle.Contracts.ReadModels.GetInstancesRequest

  defmodule PagedModel do
    use Cratis.Chronicle.ReadModels.ReadModel
    defstruct id: ""
  end

  defp sent_page do
    receive do
      {:wire_request, %GetInstancesRequest{} = request} -> {request."Page", request."PageSize"}
    after
      1000 -> raise "query request was not sent"
    end
  end

  test "asks for the first page by default", %{opts: opts} do
    Cratis.Chronicle.ReadModels.query(PagedModel, opts)

    assert sent_page() == {0, 50}
  end

  test "accepts page 0", %{opts: opts} do
    Cratis.Chronicle.ReadModels.query(PagedModel, opts ++ [page: 0, page_size: 20])

    assert sent_page() == {0, 20}
  end

  test "rejects a negative page", %{opts: opts} do
    assert_raise ArgumentError, fn ->
      Cratis.Chronicle.ReadModels.query(PagedModel, opts ++ [page: -1])
    end
  end
end
