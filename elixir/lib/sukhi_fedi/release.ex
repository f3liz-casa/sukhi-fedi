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
  @doc """
  Seed a per-site watcher actor for `domain`. Username is
  `watcher-<domain with dots → underscores>` (so `mastodon.social` →
  `watcher-mastodon_social`), and `monitored_domain` is populated so
  the UI can recover the original.
  """
  def seed_watcher(domain) when is_binary(domain) do
    username = "watcher-" <> String.replace(domain, ".", "_")

    seed_actor(username,
      display_name: "Watcher — #{domain}",
      summary: "Monitors version changes on #{domain}. Follow for updates.",
      monitored_domain: domain
    )
  end

  def seed_actor(username, opts \\ []) when is_binary(username) do
    load_app()

    display_name = Keyword.get(opts, :display_name, username)
    summary = Keyword.get(opts, :summary, "")
    monitored_domain = Keyword.get(opts, :monitored_domain)

    do_seed = fn ->
      case SukhiFedi.Repo.get_by(SukhiFedi.Schema.Account, username: username) do
        nil ->
          keys = SukhiFedi.Addons.NodeinfoMonitor.KeyGen.generate()

          %SukhiFedi.Schema.Account{}
          |> Ecto.Changeset.change(%{
            username: username,
            display_name: display_name,
            summary: summary,
            is_bot: true,
            monitored_domain: monitored_domain,
            public_key_pem: keys.public_pem,
            public_key_jwk: keys.public_jwk,
            private_key_jwk: keys.private_jwk
          })
          |> SukhiFedi.Repo.insert!()

          :created

        _existing ->
          :already_exists
      end
    end

    if Process.whereis(SukhiFedi.Repo) do
      # Running inside the live app (web request or rpc) — Repo is up.
      {:ok, do_seed.()}
    else
      # Invoked via `eval` as a one-shot — start the Repo for this call.
      {:ok, result, _apps} =
        Ecto.Migrator.with_repo(SukhiFedi.Repo, fn _repo -> do_seed.() end)

      {:ok, result}
    end
  end
end
