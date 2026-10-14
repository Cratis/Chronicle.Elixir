# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

# Round trip against a real kernel (19.56 or newer). Opt in by pointing
# CHRONICLE_INTEGRATION_CONNECTION_STRING at a development kernel, for example
# chronicle://chronicle-dev-client:chronicle-dev-secret@localhost:35006
# and run `mix test --include integration`.
defmodule Chronicle.Integration.CapturesTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  alias Chronicle.Captures

  defmodule ItemStatusChanged do
    use Chronicle.Events.EventType, id: "ItCaptureItemStatusChanged"
    defstruct status: ""
  end

  defmodule InvoiceCapture do
    use Chronicle.Captures.Capture, name: "ItCaptureInvoice", start: true

    api_source("InvoicingApi", route: "/invoices", poll: "10m")
    key("id")

    append ItemStatusChanged, when: "status" do
      set(:status, "$.status")
    end
  end

  setup_all do
    prefix = System.get_env("CHRONICLE_INTEGRATION_EVENT_STORE_PREFIX", "captures-elixir")

    {:ok, _} =
      Chronicle.Client.start_link(
        name: :captures_it_client,
        connection_string: System.fetch_env!("CHRONICLE_INTEGRATION_CONNECTION_STRING"),
        event_store:
          "#{prefix}-#{System.system_time(:millisecond)}-#{System.unique_integer([:positive])}",
        discover: false,
        event_types: [ItemStatusChanged]
      )

    lifecycle = Chronicle.Connections.Lifecycle.name_for(:captures_it_client)
    :ok = Chronicle.Connections.Lifecycle.wait_until(lifecycle, :registered, 60_000)

    :ok =
      Chronicle.ExternalServices.register(
        "InvoicingApi",
        fn builder ->
          Chronicle.ExternalServices.DefinitionBuilder.http(
            builder,
            "https://invoices.example.com"
          )
        end,
        client: :captures_it_client
      )

    :ok
  end

  @opts [client: :captures_it_client]

  test "validate/2 accepts a golden api-source declaration" do
    assert {:ok, []} =
             Captures.validate(InvoiceCapture.__chronicle_capture__(:declaration), @opts)
  end

  test "validate/2 accepts a golden events-source declaration shape" do
    declaration = """
    capture GoldenEventsCapture
      source events
        from ItCaptureItemStatusChanged
      key $eventSourceId
      append ItCaptureItemStatusChanged
        when status
        status = $.status
    """

    # The From event is a private, non-origin type here (the capture-time existence/visibility
    # checks differ from the append-time ones), so we only assert the declaration parses and
    # compiles without lexer/grammar errors - not that every semantic rule passes.
    case Captures.validate(declaration, @opts) do
      {:ok, _messages} ->
        :ok

      {:error, reason} ->
        flunk("expected the CDL compiler to accept the text; got #{inspect(reason)}")
    end
  end

  test "register, start, and list a capture" do
    assert {:ok, saved} = Captures.register(InvoiceCapture, @opts)
    assert saved.id == InvoiceCapture.__chronicle_capture__(:id)
    assert saved.declaration == InvoiceCapture.__chronicle_capture__(:declaration)

    assert :ok = Captures.start(InvoiceCapture, @opts)

    assert {:ok, captures} = Captures.list(@opts)

    assert %{status: :started} =
             Enum.find(captures, &(&1.id == InvoiceCapture.__chronicle_capture__(:id)))

    assert :ok = Captures.stop(InvoiceCapture, @opts)
    assert :ok = Captures.delete(InvoiceCapture, @opts)
  end

  test "register_discovered/1 is idempotent for an unchanged declaration" do
    discovered_opts = Keyword.put(@opts, :captures, [InvoiceCapture])

    assert :ok = Captures.register_discovered(discovered_opts)
    assert :ok = Captures.register_discovered(discovered_opts)

    assert {:ok, captures} = Captures.list(@opts)
    matching = Enum.filter(captures, &(&1.id == InvoiceCapture.__chronicle_capture__(:id)))
    assert length(matching) == 1

    assert :ok = Captures.stop(InvoiceCapture, @opts)
    assert :ok = Captures.delete(InvoiceCapture, @opts)
  end
end
