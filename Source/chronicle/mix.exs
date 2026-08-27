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
      # :inets (:httpc) and :ssl back the least-connections load-balancer
      # strategy's HTTP probes against the Chronicle kernel.
      extra_applications: [:logger, :inets, :ssl]
    ]
  end

  defp deps do
    [
      # Kept as a loose lower bound (rather than tightening to ">= 16.3.0", the
      # first version whose ConnectRequest carries ProcessId, ProcessPath,
      # MachineName, and ClientType — see Session.start_session/2): the
      # published package's own mix.exs reads its @version from a
      # CHRONICLE_VERSION build-time env var that isn't set for downstream
      # consumers, so it self-reports "0.1.0" locally regardless of the tarball
      # actually fetched. A tighter local constraint fails Mix's dependency
      # version check even though the fetched code is correct. mix.lock pins
      # the real resolved version (16.3.1 as of this change) instead.
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
      main: "Chronicle",
      extras: [
        "README.md"
      ],
      groups_for_modules: [
        Connections: [Chronicle.Connections.ConnectionString, Chronicle.Connections.Connection],
        Context: [
          Chronicle.Correlation.CorrelationId,
          Chronicle.Correlation.CorrelationIdManager,
          Chronicle.Identity,
          Chronicle.Identity.IdentityProvider,
          Chronicle.Auditing.CausationType,
          Chronicle.Auditing.CausationEntry,
          Chronicle.Auditing.CausationManager
        ],
        "Event Sourcing": [
          Chronicle.Events.EventType,
          Chronicle.Events.Migration,
          Chronicle.Events.MigrationBuilder,
          Chronicle.Events.Migrators,
          Chronicle.EventSequences.EventLog,
          Chronicle.EventSequences.EventSequence,
          Chronicle.EventSequences.TransactionalEventSequence,
          Chronicle.Events.ConcurrencyScope,
          Chronicle.Events.EventTypes,
          Chronicle.EventStores
        ],
        Transactions: [Chronicle.Transactions.UnitOfWork],
        Observers: [
          Chronicle.Reactors.Reactor,
          Chronicle.Reducers.Reducer,
          Chronicle.EventStoreSubscriptions,
          Chronicle.EventStoreSubscriptions.Subscription,
          Chronicle.EventStoreSubscriptions.Definition,
          Chronicle.EventStoreSubscriptions.DefinitionBuilder,
          Chronicle.EventStoreSubscriptions.EventType
        ],
        "Read Models": [Chronicle.ReadModels.ReadModel, Chronicle.ReadModels],
        Sinks: [Chronicle.Sinks.WellKnownSinkTypes],
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
        Constraints: [Chronicle.Events.Constraints]
      ]
    ]
  end
end
