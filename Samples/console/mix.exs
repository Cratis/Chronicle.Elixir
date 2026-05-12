# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule ConsoleSample.MixProject do
  use Mix.Project

  def project do
    [
      app: :console_sample,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      mod: {ConsoleSample.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:chronicle, "~> 0.1.0", hex: :cratis_chronicle}
    ]
  end
end
