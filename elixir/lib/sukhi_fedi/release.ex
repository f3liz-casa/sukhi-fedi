# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Release do
  @moduledoc """
  Release tasks (no Mix available). Called by the container entrypoint:

      bin/sukhi_fedi eval 'SukhiFedi.Release.migrate_all()'

  Walks `priv/repo/migrations/core/` and each enabled addon's
  `migrations_path/0`, in that order.
  """

  @app :sukhi_fedi

  def migrate_all do
    load_app()

    paths = [core_path() | addon_paths()]

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn repo ->
          Ecto.Migrator.run(repo, paths, :up, all: true)
        end)
    end
  end

  defp core_path do
    Application.app_dir(@app, Path.join(["priv", "repo", "migrations", "core"]))
  end

  defp addon_paths do
    SukhiFedi.Addon.Registry.migrations_paths()
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end

  @doc """
  Seed a local actor (Person) that remote servers can Follow. Idempotent:
  a second call with the same username is a no-op.

      bin/sukhi_fedi eval 'SukhiFedi.Release.seed_actor("watcher")'
  """
  def seed_actor(username, opts \\ []) when is_binary(username) do
    load_app()
    Application.ensure_all_started(@app)

    display_name = Keyword.get(opts, :display_name, username)
    summary = Keyword.get(opts, :summary, "")

    case SukhiFedi.Repo.get_by(SukhiFedi.Schema.Account, username: username) do
      nil ->
        keys = SukhiFedi.Addons.NodeinfoMonitor.KeyGen.generate()

        %SukhiFedi.Schema.Account{}
        |> Ecto.Changeset.change(%{
          username: username,
          display_name: display_name,
          summary: summary,
          is_bot: true,
          public_key_pem: keys.public_pem,
          public_key_jwk: keys.public_jwk,
          private_key_jwk: keys.private_jwk
        })
        |> SukhiFedi.Repo.insert!()

        {:ok, :created}

      _existing ->
        {:ok, :already_exists}
    end
  end
end
