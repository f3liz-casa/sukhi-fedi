# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule SukhiApi.MixProject do
  use Mix.Project

  def project do
    [
      app: :sukhi_api,
      version: "0.1.0",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {SukhiApi.Application, []}
    ]
  end

  defp deps do
    [
      {:jason, "~> 1.4"}
    ]
  end
end
