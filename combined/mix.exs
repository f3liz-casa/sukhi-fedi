# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Combined release shell: gateway (:sukhi_fedi) + delivery
# (:sukhi_delivery) in one BEAM for small single-box deployments.
# No code lives here — both apps stay separate projects and keep their
# own boundaries (ARCHITECTURE.md §2); this project only assembles one
# release out of the two. The 2-VM deployment keeps building from
# elixir/ and delivery/ exactly as before.
defmodule SukhiCombined.MixProject do
  use Mix.Project

  @external_resource Path.expand("../VERSION", __DIR__)
  @version Path.expand("../VERSION", __DIR__) |> File.read!() |> String.trim()

  def project do
    [
      app: :sukhi_combined,
      version: @version,
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: releases()
    ]
  end

  def application do
    [extra_applications: []]
  end

  defp deps do
    [
      {:sukhi_fedi, path: "../elixir"},
      {:sukhi_delivery, path: "../delivery"}
    ]
  end

  defp releases do
    [
      combined: [
        applications: [
          sukhi_fedi: :permanent,
          sukhi_delivery: :permanent
        ]
      ]
    ]
  end
end
