defmodule Nkeys.MixProject do
  @version "0.3.1"
  @source_url "https://github.com/nats-io/nkeys.ex"

  use Mix.Project

  def project do
    [
      app: :nkeys,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      description: "Support for nkey generation, parsing, and signing",
      package: [
        name: "nkeys",
        licenses: ["MIT"],
        links: %{
          "github" => @source_url
        }
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp docs do
    [
      main: "readme",
      logo: "nats-icon-color.svg",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: [
        "README.md"
      ]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ed25519, "~> 1.3"},
      {:kcl, "~> 1.4"},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end
end
