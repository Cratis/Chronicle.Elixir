# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.MixProject do
  use Mix.Project

  @version Path.join(__DIR__, "VERSION")
           |> File.read!()
           |> String.trim()
  @source_url "https://github.com/Cratis/Chronicle.Elixir"

  def project do
    [
      app: :cratis_chronicle,
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
      name: "cratis_chronicle",
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      maintainers: ["Cratis"],
      files: ~w(
        lib
        mix.exs
        README.md
        VERSION
        .formatter.exs
      )
    ]
  end

  defp docs do
    [
      main: "Chronicle",
      extras: [
        "README.md"
      ],
      groups_for_modules: [
        Connections: [Chronicle.Connections.ConnectionString, Chronicle.Connections.Connection],
        Context: [
          Chronicle.CorrelationId,
          Chronicle.CorrelationIdManager,
          Chronicle.Identity,
          Chronicle.IdentityProvider,
          Chronicle.CausationType,
          Chronicle.CausationEntry,
          Chronicle.CausationManager
        ],
        "Event Sourcing": [
          Chronicle.EventType,
          Chronicle.Events.Migration,
          Chronicle.Events.MigrationBuilder,
          Chronicle.Events.Migrators,
          Chronicle.EventLog,
          Chronicle.EventSequences.EventSequence,
          Chronicle.EventSequences.TransactionalEventSequence,
          Chronicle.Events.ConcurrencyScope,
          Chronicle.EventTypes,
          Chronicle.EventStores
        ],
        Transactions: [Chronicle.Transactions.UnitOfWork],
        Observers: [
          Chronicle.Reactor,
          Chronicle.Reducer,
          Chronicle.EventStoreSubscriptions,
          Chronicle.EventStoreSubscriptions.Subscription,
          Chronicle.EventStoreSubscriptions.Definition,
          Chronicle.EventStoreSubscriptions.DefinitionBuilder,
          Chronicle.EventStoreSubscriptions.EventType
        ],
        "Read Models": [Chronicle.ReadModel, Chronicle.ReadModels],
        Jobs: [
          Chronicle.Jobs,
          Chronicle.Jobs.Job,
          Chronicle.Jobs.JobProgress,
          Chronicle.Jobs.JobStatusChanged,
          Chronicle.Jobs.JobStep,
          Chronicle.Jobs.JobStepProgress,
          Chronicle.Jobs.JobStepStatusChanged
        ],
        WebHooks: [
          Chronicle.WebHooks,
          Chronicle.WebHooks.Definition,
          Chronicle.WebHooks.DefinitionBuilder,
          Chronicle.WebHooks.EventType,
          Chronicle.WebHooks.Target,
          Chronicle.WebHooks.Webhook
        ],
        Constraints: [Chronicle.Constraints]
      ]
    ]
  end
end
