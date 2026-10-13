# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Middleware do
  @moduledoc """
  Wraps the handling of an event by a reactor or reducer, for cross-cutting concerns: tracing,
  metrics, logging, impersonating the identity that caused the event, tenant scoping,
  transactional wrapping. Mirrors the .NET client's reactor middleware.

  A middleware receives the event, its `Chronicle.Events.EventContext` and `next`, a function
  that continues down the pipeline (finally reaching `handle/2` or `reduce/3`). It returns what
  the handler would return - call `next` and return its result, or return a result of its own to
  short-circuit:

      defmodule MyApp.Middleware.Timing do
        @behaviour Chronicle.Middleware
        require Logger

        @impl true
        def call(event, context, next) do
          {micros, result} = :timer.tc(fn -> next.(event, context) end)
          Logger.info("handled \#{inspect(event.__struct__)} in \#{micros}us")
          result
        end
      end

  Middleware runs in the order listed, the first being the outermost. Configure it for every
  reactor and reducer of the application:

      config :cratis_chronicle, middleware: [MyApp.Middleware.Timing]

  or for one module:

      use Chronicle.Reactors.Reactor, middleware: [MyApp.Middleware.Impersonate]
      use Chronicle.Reducers.Reducer, model: MyApp.Account, middleware: [MyApp.Middleware.Timing]

  Global middleware is the outer layer, module middleware the inner. An exception raised by a
  middleware or the handler is handled like one raised by the handler: the partition fails.

  For a reducer, `next` returns the reduced model, so a middleware that short-circuits returns
  a model (typically the one it can see through the context's current state - or simply calls
  `next`). Prefer calling `next` in reducer middleware.
  """

  @callback call(event :: struct(), context :: map(), next :: (struct(), map() -> term())) ::
              term()

  @doc "The middleware that applies to `module`: global middleware, then the module's own."
  @spec for_module(module(), :reactor | :reducer) :: [module()]
  def for_module(module, kind) do
    global = :cratis_chronicle |> Application.get_env(:middleware, []) |> List.wrap()
    global ++ module_middleware(module, kind)
  end

  @doc """
  Runs `final` (a two-arity function of event and context) through `middleware`, outermost first.
  """
  @spec run([module()], struct(), map(), (struct(), map() -> term())) :: term()
  def run([], event, context, final), do: final.(event, context)

  def run([middleware | rest], event, context, final) do
    middleware.call(event, context, fn next_event, next_context ->
      run(rest, next_event, next_context, final)
    end)
  end

  defp module_middleware(module, kind) do
    key = if kind == :reactor, do: :__chronicle_reactor__, else: :__chronicle_reducer__

    if function_exported?(module, key, 1) do
      module |> apply(key, [:middleware]) |> List.wrap()
    else
      []
    end
  rescue
    FunctionClauseError -> []
  end
end
