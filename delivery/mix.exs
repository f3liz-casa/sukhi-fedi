# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule SukhiDelivery.MixProject do
  use Mix.Project

  def project do
    [
      app: :sukhi_delivery,
      version: "0.1.0",
      elixir: "~> 1.16",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {SukhiDelivery.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # JSON
      {:jason, "~> 1.4"},

      # Database (reads outbox, writes delivery_receipts)
      {:ecto_sql, "~> 3.11"},
      {:postgrex, "~> 0.18"},

      # Job queue
      {:oban, "~> 2.18"},

      # NATS client (JetStream + Micro to Bun)
      {:gnat, "~> 1.8"},

      # HTTP client for outbound inbox POSTs
      {:req, "~> 0.5"},

      # Plug is required transitively by PromEx even when the metrics
      # server is disabled — it imports Plug.Conn at compile time.
      {:plug, "~> 1.16"},

      # Observability — mirrors the gateway's stack.
      {:telemetry, "~> 1.2"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.1"},
      {:prom_ex, "~> 1.9"},

      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:bypass, "~> 2.1", only: :test},
      {:mox, "~> 1.0", only: :test}
    ]
  end
end
