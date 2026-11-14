# Integration specs need a real kernel; opt in with CHRONICLE_INTEGRATION_CONNECTION_STRING.
exclude =
  if System.get_env("CHRONICLE_INTEGRATION_CONNECTION_STRING"), do: [], else: [integration: true]

ExUnit.start(exclude: exclude)
Code.require_file("support/append_wire_helper.exs", __DIR__)
Code.require_file("support/graph_fixtures.exs", __DIR__)
Code.require_file("support/graph_definition_snapshot.exs", __DIR__)
Code.require_file("support/graph_view_fixtures.exs", __DIR__)
Code.require_file("support/imports_fake_kernel.exs", __DIR__)
