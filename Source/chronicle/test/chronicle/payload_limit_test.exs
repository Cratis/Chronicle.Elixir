# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.PayloadLimitTest do
  use ExUnit.Case, async: false

  alias Chronicle.PayloadLimit

  setup do
    previous = Application.get_env(:cratis_chronicle, :max_payload_bytes)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:cratis_chronicle, :max_payload_bytes, previous),
        else: Application.delete_env(:cratis_chronicle, :max_payload_bytes)
    end)
  end

  test "defaults to 4 MiB" do
    assert PayloadLimit.limit() == 4_194_304
    assert PayloadLimit.check(String.duplicate("a", 4_194_304)) == :ok

    assert PayloadLimit.check(String.duplicate("a", 4_194_305)) ==
             {:error, {:payload_too_large, 4_194_305, 4_194_304}}
  end

  test "is configurable and can be disabled" do
    Application.put_env(:cratis_chronicle, :max_payload_bytes, 10)
    assert {:error, {:payload_too_large, 11, 10}} = PayloadLimit.check("12345678901")
    assert {:error, {:payload_too_large, 12, 10}} = PayloadLimit.check_all(["123456", "123456"])

    Application.put_env(:cratis_chronicle, :max_payload_bytes, :infinity)
    assert PayloadLimit.check(String.duplicate("a", 10_000_000)) == :ok
  end
end
