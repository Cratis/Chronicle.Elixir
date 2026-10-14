# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Testing.Case do
  @moduledoc """
  `ExUnit.CaseTemplate` that starts an isolated `Chronicle.Testing.start_supervised_client/1`
  before each test, puts it in the test context as `:chronicle`, and stops it in
  `on_exit`. Safe under `async: true` — every test gets its own in-memory kernel
  and client, and `start_supervised_client/1` always generates a unique event
  store name, so tests never see one another's events.

      defmodule MyApp.AccountTest do
        use Chronicle.Testing.Case,
          event_types: [MyApp.Events.AccountOpened],
          reducers: [MyApp.Reducers.AccountReducer]

        import Chronicle.Testing.Assertions

        test "opening an account appends AccountOpened", %{chronicle: client} do
          :ok =
            Chronicle.EventSequences.EventLog.append(
              "account-1",
              %MyApp.Events.AccountOpened{},
              client: client
            )

          assert_appended(client, MyApp.Events.AccountOpened, event_source_id: "account-1")
        end
      end

  Accepts the same options as `Chronicle.Testing.start_supervised_client/1`.
  """

  use ExUnit.CaseTemplate

  using opts do
    quote do
      setup do
        {:ok, client} = Chronicle.Testing.start_supervised_client(unquote(opts))
        on_exit(fn -> Chronicle.Testing.stop_supervised_client(client) end)
        %{chronicle: client}
      end
    end
  end
end
