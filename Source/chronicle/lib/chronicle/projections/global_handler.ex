# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Projections.GlobalHandler do
  @moduledoc """
  Macro for defining a mapping shared across every read model variant of a given identity,
  without repeating it on each variant module.

  A global handler is never registered as a projection on its own. Its `from/2` mappings are
  merged into every read model or declarative projection whose `variant_of/2` names the same
  identity, before that variant's own non-entering events are reclassified into update-only
  joins - so a shared mapping for a non-entering event is turned into an update-only join
  exactly like a mapping declared directly on the variant.

  ## Quick Example

      defmodule MyApp.Projections.WorkItemTitleHandler do
        use Chronicle.Projections.GlobalHandler, identity: MyApp.ReadModels.WorkItem

        from MyApp.Events.TitleChanged,
          set: [title: :title]
      end

  A mapping that targets a member some variant lacks is a declaration error
  (`Chronicle.Projections.GlobalHandlerPropertyNotOnVariant`), raised at registration time -
  not a silently skipped mapping.

  ## Registering with Chronicle.Client

      {Chronicle.Client,
        ...
        global_handlers: [MyApp.Projections.WorkItemTitleHandler]}

  Or use `otp_app:` auto-discovery - modules that export `__chronicle_global_handler__/1` are
  discovered automatically.
  """

  @doc false
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      Module.register_attribute(__MODULE__, :chronicle_projection_from, accumulate: true)

      @chronicle_global_handler_identity Keyword.fetch!(opts, :identity)

      import Chronicle.Projections.GlobalHandler, only: [from: 1, from: 2]

      @before_compile Chronicle.Projections.GlobalHandler
    end
  end

  @doc """
  Declares how an event maps onto every variant of this handler's identity.

  See `Chronicle.ReadModels.ReadModel` for full options documentation.
  """
  defmacro from(event_module, opts \\ []) do
    quote do
      @chronicle_projection_from {unquote(event_module), unquote(opts)}
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      @doc false
      def __chronicle_global_handler__(:identity), do: @chronicle_global_handler_identity

      def __chronicle_global_handler__(:from),
        do: @chronicle_projection_from |> Enum.reverse()
    end
  end
end
