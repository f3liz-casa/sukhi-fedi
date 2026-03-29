# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule SukhiFedi.MixProject do
  use Mix.Project

  def project do
    [
      app: :sukhi_fedi,
      version: "0.1.0",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      releases: [
        sukhi_fedi: [
          applications: [opentelemetry: :temporary]
        ]
      ],
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {SukhiFedi.Application, []}
    ]
  end

  defp deps do
    [
      # HTTP server
      {:bandit, "~> 1.5"},
      {:plug, "~> 1.16"},

      # JSON
      {:jason, "~> 1.4"},

      # Database
      {:ecto_sql, "~> 3.11"},
      {:postgrex, "~> 0.18"},

      # Job queue
      {:oban, "~> 2.18"},

      # NATS client
      {:gnat, "~> 1.8"},

      # HTTP client (for Oban delivery worker)
      {:req, "~> 0.5"},

      # Metrics (Prometheus)
      {:prom_ex, "~> 1.9"},

      # OpenTelemetry
      {:opentelemetry_api, "~> 1.4"},
      {:opentelemetry, "~> 1.5"},
      {:opentelemetry_exporter, "~> 1.8"},
      {:opentelemetry_ecto, "~> 1.2"},
      {:opentelemetry_oban, "~> 1.1"},
      {:teleplug, "~> 2.1"},

      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:bypass, "~> 2.1", only: :test},
      {:mox, "~> 1.0", only: :test}
    ]
  end
end