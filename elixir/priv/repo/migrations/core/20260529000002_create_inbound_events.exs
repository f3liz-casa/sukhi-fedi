# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Repo.Migrations.CreateInboundEvents do
  use Ecto.Migration

  @moduledoc """
  Time-ordered index over the inbound originals archived to the
  `inbound` object-storage bucket (Q10). The original signed bytes live
  in rustfs at `object_key`; this table is the *processed* projection
  that drives replay/rebuild — read `received_at` ascending and re-feed
  each original through `AP.Instructions`.

  `body_sha256` is unique so a remote that retries the same activity is
  idempotent: the second archive insert is a no-op (and the object key,
  being content-addressed, overwrites identical bytes).
  """

  def change do
    create table(:inbound_events) do
      add(:received_at, :utc_datetime_usec, null: false)
      add(:actor_uri, :string)
      add(:activity_type, :string)
      add(:activity_id, :string)
      add(:object_key, :string, null: false)
      add(:body_sha256, :string, null: false)
      # "shared" | "user" — which inbox the activity arrived on.
      add(:inbox, :string)
      timestamps(type: :utc_datetime, inserted_at: :created_at, updated_at: false)
    end

    create(unique_index(:inbound_events, [:body_sha256]))
    create(index(:inbound_events, [:received_at]))
    create(index(:inbound_events, [:actor_uri]))
  end
end
