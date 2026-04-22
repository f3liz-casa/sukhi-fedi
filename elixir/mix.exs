# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule SukhiFedi.MixProject do
  use Mix.Project

  def project do
    [
      app: :sukhi_fedi,
      version: "0.1.0",
      elixir: "~> 1.16",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :os_mon],
      mod: {SukhiFedi.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

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

      # HTTP client
      {:req, "~> 0.5"},

      # Lightweight observability: telemetry + PromEx (Prometheus).
      # Distributed tracing is intentionally omitted — use structured
      # Logger messages and Prometheus histograms instead.
      {:telemetry, "~> 1.2"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.1"},
      {:prom_ex, "~> 1.9"},

      # Rate limiting (ETS-backed, node-local).
      {:hammer, "~> 6.1"},

      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:bypass, "~> 2.1", only: :test},
      {:mox, "~> 1.0", only: :test}
    ]
  end
end
