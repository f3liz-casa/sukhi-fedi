# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Repo.Migrations.CreateBubbleInstances do
  use Ecto.Migration

  # The allow-set behind the "bubble" (ご近所) timeline — a small,
  # admin-curated list of trusted remote instances whose public posts
  # surface in a calm, subtractive feed. Mirrors `instance_blocks`
  # (domain + who added it), but as an allow-list rather than a
  # block-list; managed via eval for now (no admin UI).
  def change do
    create table(:bubble_instances) do
      add :domain, :string, null: false
      add :created_by_id, references(:accounts, on_delete: :nilify_all)
      timestamps()
    end

    create unique_index(:bubble_instances, [:domain])
  end
end
