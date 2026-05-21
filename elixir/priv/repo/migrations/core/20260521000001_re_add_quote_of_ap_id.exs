# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Repo.Migrations.ReAddQuoteOfApId do
  use Ecto.Migration

  @moduledoc """
  Re-adds `notes.quote_of_ap_id`, dropped in
  `20260519100008_drop_unused_ap_id_columns` as unused.

  It now has readers: `AP.Instructions.maybe_mirror_create_note/1` and
  `Federation.NoteFetcher` store the Misskey quote-note reference here
  so inbound 引用ノート round-trip instead of silently losing the link.
  """

  def change do
    alter table(:notes) do
      add :quote_of_ap_id, :text
    end

    create index(:notes, [:quote_of_ap_id])
  end
end
