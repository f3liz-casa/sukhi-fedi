# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Repo.Migrations.CreateDeliveryReceipts do
  use Ecto.Migration

  def change do
    create table(:delivery_receipts) do
      add :activity_id, :string, null: false
      add :inbox_url, :text, null: false
      add :status, :string, null: false
      add :delivered_at, :utc_datetime_usec
      add :inserted_at, :utc_datetime_usec, null: false, default: fragment("now()")
    end

    # per-inbox idempotency: same activity to same inbox is delivered once.
    create unique_index(:delivery_receipts, [:activity_id, :inbox_url])
  end
end
