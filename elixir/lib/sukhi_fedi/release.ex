# SPDX-License-Identifier: MPL-2.0
defmodule SukhiFedi.Release do
  @moduledoc """
  Tasks for running inside an Elixir release (no Mix available).

  Usage from kamal:
    kamal app exec --interactive --reuse "bin/sukhi_fedi eval 'SukhiFedi.Release.migrate()'"
  """

  @app :sukhi_fedi

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
