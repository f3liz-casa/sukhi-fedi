# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule SukhiApi.MixProject do
  use Mix.Project

  # Single source of truth at repo root, shared with :sukhi_fedi.
  @external_resource Path.expand("../VERSION", __DIR__)
  @version Path.expand("../VERSION", __DIR__) |> File.read!() |> String.trim()

  def project do
    [
      app: :sukhi_api,
      version: @version,
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
