# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Repo.Migrations.CreateNotesDrafts do
  use Ecto.Migration

  # A compose draft the author is still writing — the cross-device half of
  # the SPA's local `sf.compose_draft` cache. It holds only the small text
  # fields the composer restores (text, spoiler, sensitive, visibility);
  # media ids are deliberately not stored (uploaded ids expire/GC, so a
  # restored one would dangle). A draft is never federated and never
  # published from here: the row is private to one account and is pruned
  # once the note is actually posted. One draft per account — the unique
  # index makes save an upsert.
  def change do
    create table(:notes_drafts) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :text, :text, null: false, default: ""
      add :spoiler, :text, null: false, default: ""
      add :sensitive, :boolean, null: false, default: false
      add :visibility, :string, null: false, default: "public"
      timestamps()
    end

    create unique_index(:notes_drafts, [:account_id])
  end
end
