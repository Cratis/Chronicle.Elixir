# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.MiddlewareTest do
  use ExUnit.Case, async: false

  alias Chronicle.Middleware

  defmodule Evt do
    use Chronicle.Events.EventType, id: "middleware-evt"
    defstruct [:v]
  end

  defmodule Tag do
    @behaviour Chronicle.Middleware
    @impl true
    def call(event, context, next) do
      send(self(), {:before, __MODULE__})
      result = next.(event, context)
      send(self(), {:after, __MODULE__})
      result
    end
  end

  defmodule Outer do
    @behaviour Chronicle.Middleware
    @impl true
    def call(event, context, next) do
      send(self(), {:before, __MODULE__})
      next.(event, Map.put(context, :decorated, true))
    end
  end

  defmodule Stop do
    @behaviour Chronicle.Middleware
    @impl true
    def call(_event, _context, _next), do: {:error, :denied}
  end

  defmodule WithMiddleware do
    use Chronicle.Reactors.Reactor, middleware: [Tag]
    @handles Evt
    @impl true
    def handle(_e, _c), do: :ok
  end

  setup do
    on_exit(fn -> Application.delete_env(:cratis_chronicle, :middleware) end)
  end

  test "middleware runs outermost first and sees the result" do
    result = Middleware.run([Outer, Tag], %Evt{}, %{}, fn _e, ctx -> {:final, ctx} end)

    assert result == {:final, %{decorated: true}}
    assert_received {:before, Outer}
    assert_received {:before, Tag}
    assert_received {:after, Tag}
  end

  test "a middleware can short-circuit" do
    assert Middleware.run([Stop, Tag], %Evt{}, %{}, fn _, _ -> flunk("not reached") end) ==
             {:error, :denied}

    refute_received {:before, Tag}
  end

  test "no middleware calls the handler directly" do
    assert Middleware.run([], %Evt{}, %{}, fn _, _ -> :handled end) == :handled
  end

  test "global middleware wraps module middleware" do
    Application.put_env(:cratis_chronicle, :middleware, [Outer])
    assert Middleware.for_module(WithMiddleware, :reactor) == [Outer, Tag]
    Application.delete_env(:cratis_chronicle, :middleware)
    assert Middleware.for_module(WithMiddleware, :reactor) == [Tag]
  end

  test "a module that is not a reactor has only the global middleware" do
    Application.put_env(:cratis_chronicle, :middleware, Tag)
    assert Middleware.for_module(String, :reactor) == [Tag]
  end
end
