# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Repo.Migrations.CreateScheduledStatuses do
  use Ecto.Migration

  # A status the author asked us to publish later. We keep the exact
  # Mastodon-shaped create params (`status`, `visibility`, `media_ids`,
  # `poll`, …) verbatim in `params` and a `publish_at` instant; an Oban
  # job (id stored here so a cancel can delete it) wakes at `publish_at`
  # and runs the same `create_status` path a live POST would, so nothing
  # about the note's validation, federation or outbox changes — only its
  # timing. Owned by one account; deleting the account drops its
  # schedules. The auto-delete half (self-deleting notes) is intentionally
  # not built here.
  def change do
    create table(:scheduled_statuses) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :params, :map, null: false, default: %{}
      add :scheduled_at, :utc_datetime, null: false
      add :oban_job_id, :bigint
      timestamps()
    end

    create index(:scheduled_statuses, [:account_id, :scheduled_at])
  end
end
