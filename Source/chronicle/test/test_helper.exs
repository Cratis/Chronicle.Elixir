# Integration specs need a real kernel; opt in with CHRONICLE_INTEGRATION_CONNECTION_STRING.
exclude =
  if System.get_env("CHRONICLE_INTEGRATION_CONNECTION_STRING"), do: [], else: [integration: true]

ExUnit.start(exclude: exclude)
Code.require_file("support/append_wire_helper.exs", __DIR__)
