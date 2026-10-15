# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Connections.CredentialScrubberTest do
  use ExUnit.Case, async: false

  alias Chronicle.Connections.{CredentialRegistry, CredentialScrubber}

  @secret "scrubber-secret-value"

  setup do
    on_exit(fn -> CredentialRegistry.forget(@secret) end)
  end

  describe "CredentialScrubber" do
    test "redacts header pairs and map entries named like credential headers" do
      scrubbed =
        CredentialScrubber.term(%{
          "Authorization" => "Bearer abc.def",
          "x" => [{"api-key", @secret}, {"content-type", "application/grpc"}]
        })

      refute inspect(scrubbed) =~ "abc.def"
      refute inspect(scrubbed) =~ @secret
      assert inspect(scrubbed) =~ "application/grpc"
    end

    test "redacts remembered values and bearer tokens in text" do
      CredentialRegistry.remember(@secret)

      assert CredentialScrubber.text("failed with #{@secret} here") ==
               "failed with [redacted] here"

      assert CredentialScrubber.text("Authorization: Bearer abc.DEF-123") =~ "Bearer [redacted]"

      assert CredentialScrubber.text(~s|{\\"api-key\\", \\"hunter2hunter2\\"}|) =~
               "[redacted]"

      assert CredentialScrubber.text("nothing to see") == "nothing to see"
    end

    test "walks improper lists and charlists without crashing" do
      CredentialRegistry.remember(@secret)

      assert [1, 2 | "tail"] = CredentialScrubber.term([1, 2 | "tail"])

      assert [{:a, "x [redacted]"} | "end"] =
               CredentialScrubber.term([{:a, "x #{@secret}"} | "end"])

      assert ~c"plain" == CredentialScrubber.chardata(~c"plain")
    end

    test "leaves terms without credentials identical" do
      term = %{a: [1, {:b, "c"}], d: %RuntimeError{message: "boom"}}
      assert CredentialScrubber.term(term) == term
    end
  end
end
