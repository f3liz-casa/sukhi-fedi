# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Release do
  @moduledoc """
  Release tasks (no Mix available). Called by the container entrypoint:

      bin/sukhi_fedi eval 'SukhiFedi.Release.migrate_all()'

  Walks `priv/repo/migrations/core/` and each enabled addon's
  `migrations_path/0`, in that order.
  """

  import Ecto.Query, only: [from: 2]

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

  @doc """
  One-shot: for every `MonitoredInstance` that already has at least one
  snapshot, publish an "監視を始めました" Note using the latest snapshot.
  Use after `backfill_monitored_instances/0` on a deployment where the
  initial polls already ran through PollWorker's old :initial branch
  (pre-v0.1.22), which recorded snapshots but did not publish.

      bin/sukhi_fedi eval 'SukhiFedi.Release.publish_initial_notes_for_backfill()'
  """
  def publish_initial_notes_for_backfill do
    load_app()

    do_publish = fn ->
      alias SukhiFedi.Repo
      alias SukhiFedi.Addons.NodeinfoMonitor
      alias SukhiFedi.Schema.{MonitoredInstance, NodeinfoSnapshot}

      from(m in MonitoredInstance, order_by: [asc: m.domain])
      |> Repo.all()
      |> Enum.map(fn mi ->
        snap =
          from(s in NodeinfoSnapshot,
            where: s.monitored_instance_id == ^mi.id,
            order_by: [desc: s.polled_at],
            limit: 1
          )
          |> Repo.one()

        if snap do
          NodeinfoMonitor.publish_initial_note(mi, %{
            software_name: snap.software_name,
            version: snap.version
          })
          |> case do
            {:ok, _note} -> {mi.domain, :ok}
            other -> {mi.domain, other}
          end
        else
          {mi.domain, :no_snapshot}
        end
      end)
    end

    result =
      if Process.whereis(SukhiFedi.Repo) do
        do_publish.()
      else
        {:ok, r, _apps} = Ecto.Migrator.with_repo(SukhiFedi.Repo, fn _repo -> do_publish.() end)
        r
      end

    IO.inspect(result, label: :publish_initial_notes_for_backfill)
    {:ok, result}
  end

  @doc """
  One-shot: delete every Note owned by a watcher bot via the standard
  Notes.delete_note path, so each removal fans out as a proper
  Delete(Note) to federation instead of vanishing silently. Useful
  when republishing watcher notes after a Bun translator fix — the
  old ghost copies on remote timelines need a Delete to clear first.

      bin/sukhi_fedi eval 'SukhiFedi.Release.delete_all_watcher_notes()'
  """
  def delete_all_watcher_notes do
    load_app()

    do_delete = fn ->
      alias SukhiFedi.{Repo, Notes}
      alias SukhiFedi.Schema.{Account, Note}

      Repo.all(
        from(n in Note,
          join: a in Account,
          on: a.id == n.account_id,
          where: not is_nil(a.monitored_domain),
          select: {a.id, n.id}
        )
      )
      |> Enum.map(fn {account_id, note_id} ->
        Notes.delete_note(account_id, note_id) |> elem(0) |> then(&{note_id, &1})
      end)
    end

    result =
      if Process.whereis(SukhiFedi.Repo) do
        do_delete.()
      else
        {:ok, r, _apps} = Ecto.Migrator.with_repo(SukhiFedi.Repo, fn _repo -> do_delete.() end)
        r
      end

    IO.inspect(result, label: :delete_all_watcher_notes)
    {:ok, result}
  end

  @doc """
  One-shot: insert a `monitored_instances` row for every existing
  watcher `Account` that doesn't have one yet. Safe to run multiple
  times (no-op on conflict).

      bin/sukhi_fedi eval 'SukhiFedi.Release.backfill_monitored_instances()'
  """
  def backfill_monitored_instances do
    load_app()

    do_backfill = fn ->
      alias SukhiFedi.Repo
      alias SukhiFedi.Schema.{Account, MonitoredInstance}

      from(a in Account, where: not is_nil(a.monitored_domain))
      |> Repo.all()
      |> Enum.map(fn a ->
        %MonitoredInstance{}
        |> MonitoredInstance.changeset(%{domain: a.monitored_domain, actor_id: a.id})
        |> Repo.insert(on_conflict: :nothing, conflict_target: :domain)
      end)
    end

    if Process.whereis(SukhiFedi.Repo) do
      {:ok, do_backfill.()}
    else
      {:ok, result, _apps} =
        Ecto.Migrator.with_repo(SukhiFedi.Repo, fn _repo -> do_backfill.() end)

      {:ok, result}
    end
  end
end
