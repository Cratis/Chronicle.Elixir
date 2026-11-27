# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Cratis.Chronicle.MixProject do
  use Mix.Project

  @version Path.join(__DIR__, "VERSION")
           |> File.read!()
           |> String.trim()
  @source_url "https://github.com/Cratis/Chronicle.Elixir"

  def project do
    [
      app: :cratis_chronicle,
      version: @version,
      # googleapis 0.1 requires Elixir 1.18.
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      # Protocol consolidation runs after `lib/` compiles, which would freeze the
      # Jason.Encoder dispatch table before ExUnit loads `test/**/*_test.exs`. Concept
      # specs define their fixture concepts (and therefore new Jason.Encoder
      # implementations) inline inside test modules by house convention, so
      # consolidation must be skipped in :test — otherwise a fixture's implementation
      # is silently ignored and encoding raises Protocol.UndefinedError.
      consolidate_protocols: Mix.env() != :test,
      # Specs are `*_test.exs` (the older ones) or any script in a `for_*` folder (the BDD layout, with no
      # `_test` suffix); `given/` holds shared contexts the specs load themselves.
      test_load_filters: [
        &String.ends_with?(&1, "_test.exs"),
        &(String.contains?(&1, "/for_") and not String.contains?(&1, "/given/"))
      ],
      test_ignore_filters: [&String.contains?(&1, "/given/")],
      deps: deps(),
      description:
        "Idiomatic Elixir client for Cratis Chronicle, the open-source event-sourcing database and runtime",
      package: package(),
      source_url: @source_url,
      homepage_url: "https://www.cratis.io/chronicle/clients/elixir/",
      docs: docs()
    ]
  end

  def application do
    [
      # :inets (:httpc) and :ssl back the least-connections load-balancer
      # strategy's HTTP probes against the Chronicle kernel.
      extra_applications: [:logger, :inets, :ssl]
    ]
  end

  defp deps do
    [
      {:cratis_chronicle_contracts, "~> 19.188"},
      {:grpc, "~> 1.0.6"},
      {:mint, "~> 1.11"},
      {:telemetry, "~> 1.0"},
      {:opentelemetry_api, "~> 1.4"},
      {:jason, "~> 1.4"},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      name: "cratis_chronicle",
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Chronicle" => "https://github.com/Cratis/Chronicle",
        "Documentation" => "https://www.cratis.io/chronicle/",
        "Cratis" => "https://www.cratis.io"
      },
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
      main: "Cratis.Chronicle",
      extras: [
        "README.md"
      ],
      groups_for_modules: [
        Connections: [
          Cratis.Chronicle.Connections.ConnectionString,
          Cratis.Chronicle.Connections.Connection
        ],
        Context: [
          Cratis.Chronicle.Correlation.CorrelationId,
          Cratis.Chronicle.Correlation.CorrelationIdManager,
          Cratis.Chronicle.Identity,
          Cratis.Chronicle.Identity.IdentityProvider,
          Cratis.Chronicle.Auditing.CausationType,
          Cratis.Chronicle.Auditing.CausationEntry,
          Cratis.Chronicle.Auditing.CausationManager
        ],
        "Event Sourcing": [
          Cratis.Chronicle.Events.EventType,
          Cratis.Chronicle.Events.Migration,
          Cratis.Chronicle.Events.MigrationBuilder,
          Cratis.Chronicle.Events.Migrators,
          Cratis.Chronicle.EventSequences.EventLog,
          Cratis.Chronicle.EventSequences.EventSequence,
          Cratis.Chronicle.EventSequences.TransactionalEventSequence,
          Cratis.Chronicle.Events.ConcurrencyScope,
          Cratis.Chronicle.Events.EventTypes,
          Cratis.Chronicle.EventSources,
          Cratis.Chronicle.EventSources.EventSource,
          Cratis.Chronicle.EventSources.EventSourceDefinition,
          Cratis.Chronicle.EventSources.EventStream,
          Cratis.Chronicle.EventSources.ConcurrencyDimensions,
          Cratis.Chronicle.EventStores
        ],
        Transactions: [Cratis.Chronicle.Transactions.UnitOfWork],
        Imports: [
          Cratis.Chronicle.Imports,
          Cratis.Chronicle.Imports.Session,
          Cratis.Chronicle.Imports.ImportResult,
          Cratis.Chronicle.Imports.ImportProgress,
          Cratis.Chronicle.Imports.ImportRejection
        ],
        Observers: [
          Cratis.Chronicle.Reactors.Reactor,
          Cratis.Chronicle.Reducers.Reducer,
          Cratis.Chronicle.EventStoreSubscriptions,
          Cratis.Chronicle.EventStoreSubscriptions.Subscription,
          Cratis.Chronicle.EventStoreSubscriptions.Definition,
          Cratis.Chronicle.EventStoreSubscriptions.DefinitionBuilder,
          Cratis.Chronicle.EventStoreSubscriptions.EventType
        ],
        "Read Models": [Cratis.Chronicle.ReadModels.ReadModel, Cratis.Chronicle.ReadModels],
        "Graph Projections": [
          Cratis.Chronicle.Graphs.Graph,
          Cratis.Chronicle.Graphs.Node,
          Cratis.Chronicle.Graphs.Edge,
          Cratis.Chronicle.Graphs.View,
          Cratis.Chronicle.Graphs.ViewDefinition
        ],
        Sinks: [Cratis.Chronicle.Sinks.WellKnownSinkTypes],
        Jobs: [
          Cratis.Chronicle.Jobs,
          Cratis.Chronicle.Jobs.Job,
          Cratis.Chronicle.Jobs.JobProgress,
          Cratis.Chronicle.Jobs.JobStatusChanged,
          Cratis.Chronicle.Jobs.JobStep,
          Cratis.Chronicle.Jobs.JobStepProgress,
          Cratis.Chronicle.Jobs.JobStepStatusChanged
        ],
        WebHooks: [
          Cratis.Chronicle.WebHooks,
          Cratis.Chronicle.WebHooks.Definition,
          Cratis.Chronicle.WebHooks.DefinitionBuilder,
          Cratis.Chronicle.WebHooks.EventType,
          Cratis.Chronicle.WebHooks.Target,
          Cratis.Chronicle.WebHooks.Webhook
        ],
        Constraints: [Cratis.Chronicle.Events.Constraints]
      ]
    ]
  end
end
