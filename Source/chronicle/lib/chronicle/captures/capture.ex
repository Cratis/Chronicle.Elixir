# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Captures.Capture do
  @moduledoc """
  DSL for defining discoverable Chronicle captures.

  A capture turns data that arrives from outside the event log — an external API, a webhook,
  or another event store's public events — into events appended to this event store. The DSL
  compiles at build time to [Capture Declaration Language](https://github.com/Cratis/Chronicle/blob/main/Documentation/captures/capture-declaration-language/index.md)
  (CDL) text, the same text format the Chronicle kernel's Workbench and `SaveCapture` accept.

  ## Example

      defmodule MyApp.Captures.InvoiceCapture do
        use Chronicle.Captures.Capture, name: "InvoiceCapture"

        api_source "InvoicingApi", route: "/invoices", poll: "10m"

        key "id"

        append MyApp.Events.InvoiceStatusChanged, when: "status" do
          set :status, "$.status"
        end
      end

  ## Options for `use Chronicle.Captures.Capture`

    * `:name` — the capture's name. Defaults to the module's last segment.
    * `:id` — the capture's stable id (a GUID string). Defaults to a deterministic UUIDv5
      derived from the module's full name, so re-registering the same module updates the
      same kernel-side capture instead of creating a new one.
    * `:start` — when `true`, `Chronicle.Captures.Registrar` starts the capture after
      registering it (opt-in; defaults to `false`, leaving a freshly saved capture stopped).

  ## Sources (exactly one is required)

    * `api_source/1,2` — polls an [External Service](https://github.com/Cratis/Chronicle/blob/main/Documentation/external-services/index.md)
      by name. Options: `:route`, `:poll` (e.g. `poll: "10m"`).
    * `webhook_source/1` — an inbound webhook at the given path.
    * `events_source/1` — captures from the public events of another event store, given as a
      list of registered `Chronicle.Events.EventType` modules.

  Only `api_source` and `events_source` captures are run by the Chronicle engine as of
  Chronicle 19.6; see the CDL documentation linked above.

  ## Key

  `key/1` names the property path (on the captured item) used to identify and diff it between
  observations. For an `events_source`, use `"$eventSourceId"` to key on the incoming event's
  event source.

  ## Map (optional)

  `map do ... end` declares operations applied to the captured item before `append` reads it:

      map do
        rename :full_name, :fornavn
        template :greeting, "Hello, ${fornavn}"
        translate :status, :status, [{"aktiv", "active"}, {"inaktiv", "inactive"}]
        split :full_name, by: ",", into: [:first_name, :last_name]
      end

  ## Append

  The kernel's CDL parser requires an append's event type to start with an uppercase letter
  (letters, digits, and underscores only - no hyphens), even though it is otherwise free to
  register event types with any id. Register the event type you intend to append from a
  capture with a matching id (`id: "InvoiceStatusChanged"` rather than
  `id: "invoice-status-changed"`); `append/2,3` raises `ArgumentError` at compile time
  otherwise, rather than letting the capture fail validation on the kernel.

  `append/2,3` declares an event to append when its `when:` condition matches. `set/2` inside
  its block maps a target field of the event's struct from a source expression (`"$.path"` for
  the current payload, `"$previous.path"` for the previous one, `"$context.<property>"` for
  the capture/event context, `"$env.VARIABLE"` for an environment lookup):

      append MyApp.Events.CustomerChanged, when: {:any, ["firstName", "lastName"]} do
        set :first_name, "$.firstName"
      end

  `when:` accepts:

    * a string — `when: "status"` (fires when that property changes)
    * `{:any, [...]}` / `{:all, [...]}` — `"p1 or p2"` / `"p1 and p2"`
    * `{:transition, property, from, to}` — `"status from a to b"`
    * `:added` / `:removed`
    * `{:expression, "template"}` — a raw CDL expression

  ## Nested and children scopes

      nested :billing_address do
        map do
          rename :street, :"fakturaAdresse.gate"
        end

        append MyApp.Events.BillingAddressChanged, when: "street" do
          set :street, "$.street"
        end
      end

      children :line_items, identified_by: :line_number do
        append MyApp.Events.ItemAdded, when: :added do
          set :line_number, "$.lineNumber"
        end
      end

  ## Introspection

      MyApp.Captures.InvoiceCapture.__chronicle_capture__(:id)
      MyApp.Captures.InvoiceCapture.__chronicle_capture__(:name)
      MyApp.Captures.InvoiceCapture.__chronicle_capture__(:declaration)

  ## Registering with Chronicle.Client

      {Chronicle.Client,
        ...
        captures: [MyApp.Captures.InvoiceCapture]}

  Or use `otp_app:` auto-discovery — modules that export `__chronicle_capture__/1` are
  discovered automatically. See `Chronicle.Captures.Registrar` for how registration happens.
  """

  alias Chronicle.Captures.Capture.Parser
  alias Chronicle.Captures.{Declaration, MissingCaptureKey, MissingCaptureSourceConfiguration}

  @doc false
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      Module.register_attribute(__MODULE__, :chronicle_capture_sources, accumulate: true)
      Module.register_attribute(__MODULE__, :chronicle_capture_appends, accumulate: true)
      Module.register_attribute(__MODULE__, :chronicle_capture_nested, accumulate: true)
      Module.register_attribute(__MODULE__, :chronicle_capture_children, accumulate: true)
      Module.register_attribute(__MODULE__, :chronicle_capture_key, [])
      Module.register_attribute(__MODULE__, :chronicle_capture_map, [])

      @chronicle_capture_name Keyword.get(
                                opts,
                                :name,
                                __MODULE__ |> Module.split() |> List.last()
                              )
      @chronicle_capture_id Keyword.get(opts, :id, Declaration.deterministic_id(__MODULE__))
      @chronicle_capture_start Keyword.get(opts, :start, false)
      @chronicle_capture_key nil
      @chronicle_capture_map nil

      import Chronicle.Captures.Capture,
        only: [
          api_source: 1,
          api_source: 2,
          webhook_source: 1,
          events_source: 1,
          key: 1,
          map: 1,
          append: 2,
          append: 3,
          nested: 2,
          children: 3
        ]

      @before_compile Chronicle.Captures.Capture
    end
  end

  @doc "Declares an API source, polling the named External Service."
  defmacro api_source(api, opts \\ []) do
    quote do
      @chronicle_capture_sources {:api, unquote(api), unquote(opts)}
    end
  end

  @doc "Declares an inbound webhook source at the given path."
  defmacro webhook_source(path) do
    quote do
      @chronicle_capture_sources {:webhook, unquote(path), []}
    end
  end

  @doc """
  Declares an events source, capturing from the public events of another event store.

  `events` is a list of registered `Chronicle.Events.EventType` modules.
  """
  defmacro events_source(events) do
    quote do
      @chronicle_capture_sources {:events,
                                  Enum.map(
                                    unquote(events),
                                    &Chronicle.Captures.Capture.__event_type_id__/1
                                  )}
    end
  end

  @doc "Names the property path used to identify and diff a captured item."
  defmacro key(property_path) do
    quote do
      @chronicle_capture_key to_string(unquote(property_path))
    end
  end

  @doc "Declares map operations for the capture's root scope. See the moduledoc."
  defmacro map(do: block) do
    operations = Macro.escape(Parser.map_operations(block))

    quote do
      @chronicle_capture_map unquote(operations)
    end
  end

  @doc "Appends an event when its `when:` condition matches. See the moduledoc."
  defmacro append(event_module, opts \\ [], do: block) do
    append_definition = Macro.escape(Parser.build_append(event_module, opts, block, __CALLER__))

    quote do
      @chronicle_capture_appends unquote(append_definition)
    end
  end

  @doc "Declares a nested object scope. See the moduledoc."
  defmacro nested(object_path, do: block) do
    {map_ops, appends} = Parser.parse_scope(block, __CALLER__)
    definition = {Macro.expand(object_path, __CALLER__) |> to_string(), map_ops, appends}

    quote do
      @chronicle_capture_nested unquote(Macro.escape(definition))
    end
  end

  @doc "Declares a child collection scope, identified by a per-item key. See the moduledoc."
  defmacro children(collection_path, opts, do: block) do
    {map_ops, appends} = Parser.parse_scope(block, __CALLER__)

    identified_by =
      opts |> Keyword.fetch!(:identified_by) |> Macro.expand(__CALLER__) |> to_string()

    collection = collection_path |> Macro.expand(__CALLER__) |> to_string()
    definition = {collection, identified_by, map_ops, appends}

    quote do
      @chronicle_capture_children unquote(Macro.escape(definition))
    end
  end

  @doc false
  def __event_type_id__(event_module), do: Parser.event_type_id(event_module)

  @doc false
  defmacro __before_compile__(env) do
    module = env.module
    name = Module.get_attribute(module, :chronicle_capture_name)
    sources = module |> Module.get_attribute(:chronicle_capture_sources) |> Enum.reverse()
    key = Module.get_attribute(module, :chronicle_capture_key)

    source = validate_source!(sources, name)
    validate_key!(key, name)

    declaration_map = %{
      name: name,
      source: source,
      key: key,
      map: Module.get_attribute(module, :chronicle_capture_map),
      appends: module |> Module.get_attribute(:chronicle_capture_appends) |> Enum.reverse(),
      nested: module |> Module.get_attribute(:chronicle_capture_nested) |> Enum.reverse(),
      children: module |> Module.get_attribute(:chronicle_capture_children) |> Enum.reverse()
    }

    declaration_text = Declaration.render(declaration_map)
    id = Module.get_attribute(module, :chronicle_capture_id)

    start? = Module.get_attribute(module, :chronicle_capture_start)

    quote do
      @doc false
      def __chronicle_capture__(:id), do: unquote(id)
      def __chronicle_capture__(:name), do: unquote(name)
      def __chronicle_capture__(:declaration), do: unquote(declaration_text)
      def __chronicle_capture__(:start?), do: unquote(start?)
    end
  end

  defp validate_source!([], name),
    do: raise(MissingCaptureSourceConfiguration, capture: name, count: 0)

  defp validate_source!([source], _name), do: source

  defp validate_source!(sources, name),
    do: raise(MissingCaptureSourceConfiguration, capture: name, count: length(sources))

  defp validate_key!(nil, name), do: raise(MissingCaptureKey, capture: name)
  defp validate_key!(_key, _name), do: :ok
end
