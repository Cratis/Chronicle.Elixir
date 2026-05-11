# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.MixProject do
  use Mix.Project

  @version System.get_env("CHRONICLE_VERSION") || "0.1.0"
  @source_url "https://github.com/Cratis/Chronicle.Elixir"

  def project do
    [
      app: :chronicle,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Idiomatic Elixir client for Chronicle event sourcing",
      package: package(),
      source_url: @source_url,
      homepage_url: @source_url,
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:cratis_chronicle_contracts, ">= 0.1.0"},
      {:grpc, "~> 0.11"},
      {:mint, "~> 1.7"},
      {:jason, "~> 1.4"},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      name: "chronicle",
      organization: "cratis",
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      maintainers: ["Cratis"],
      files: ~w(lib mix.exs README.md .formatter.exs)
    ]
  end

  defp docs do
    [
      main: "Chronicle",
      extras: ["README.md"],
      groups_for_modules: [
        Connections: [Chronicle.Connections.ConnectionString, Chronicle.Connections.Connection],
        "Event Sourcing": [Chronicle.EventType, Chronicle.EventLog, Chronicle.EventTypes],
        Observers: [Chronicle.Reactor, Chronicle.Reducer],
        "Read Models": [Chronicle.ReadModel, Chronicle.ReadModels],
        Constraints: [Chronicle.Constraints]
      ]
    ]
  end
end
