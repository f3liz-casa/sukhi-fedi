# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Repo.Migrations.CreateOutboundEvents do
  use Ecto.Migration

  @moduledoc """
  Time-ordered index over the outbound originals archived to the `outbound`
  object-storage bucket — the mirror of `inbound_events`. The `outbox` table
  holds only the *intent* of a delivery and is pruned; this keeps a durable
  record of what bytes were actually POSTed to each remote inbox and how the
  remote answered.

  The signed JSON body lives in rustfs at `object_key`, zstd-compressed and
  content-addressed by `body_sha256`. The same activity sent to many inboxes
  shares one object (identical body); the audit unit is the *delivery*, so
  the index is unique on `(activity_id, inbox_url)` — like `delivery_receipts`,
  plus a pointer into object storage. A retried delivery's archive insert is
  a no-op on that unique key.
  """

  def change do
    create table(:outbound_events) do
      add(:delivered_at, :utc_datetime_usec, null: false)
      add(:actor_uri, :string)
      add(:activity_id, :string, null: false)
      # URLs exceed the 255 default — `:text`, like delivery_receipts.inbox_url.
      add(:inbox_url, :text, null: false)
      # "delivered" | "gone" | "failed"
      add(:status, :string)
      # HTTP status the remote returned; null on a transport-level error.
      add(:response_status, :integer)
      add(:object_key, :string, null: false)
      add(:body_sha256, :string, null: false)
      timestamps(type: :utc_datetime, inserted_at: :created_at, updated_at: false)
    end

    create(unique_index(:outbound_events, [:activity_id, :inbox_url]))
    create(index(:outbound_events, [:delivered_at]))
    create(index(:outbound_events, [:body_sha256]))
  end
end
