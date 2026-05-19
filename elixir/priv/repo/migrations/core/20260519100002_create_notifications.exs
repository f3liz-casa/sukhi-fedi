# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Repo.Migrations.CreateNotifications do
  use Ecto.Migration

  @moduledoc """
  Mastodon-compatible notifications.

  Rows are written by `SukhiFedi.AP.Instructions` on inbound activities
  (follow, favourite, reblog) and by `SukhiFedi.Notes` on local-to-local
  interactions. Read by `GET /api/v1/notifications`.

  `dismissed_at` is the soft-delete used by `POST /:id/dismiss` and
  bulk `POST /clear`. `read_at` is kept for clients that ever distinguish
  it from dismissal (Mastodon's API doesn't, but it costs nothing to
  reserve the column).
  """

  def change do
    create table(:notifications) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :from_account_id, references(:accounts, on_delete: :delete_all)
      add :note_id, references(:notes, on_delete: :delete_all)

      add :type, :string, null: false
      add :read_at, :utc_datetime
      add :dismissed_at, :utc_datetime
      add :created_at, :utc_datetime, null: false
    end

    create index(:notifications, [:account_id, :id])
    create index(:notifications, [:account_id, :type])

    # Idempotency: a single (recipient, actor, kind, note) shouldn't
    # produce duplicates if the same activity is delivered twice.
    create unique_index(
             :notifications,
             [:account_id, :from_account_id, :type, :note_id],
             name: :notifications_dedup_index
           )
  end
end
