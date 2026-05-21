# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Repo.Migrations.ReAddMfm do
  use Ecto.Migration

  @moduledoc """
  Re-adds `notes.mfm`, dropped in `20260519100008_drop_unused_ap_id_columns`
  as unused.

  It now has a reader: the inbound ingest paths
  (`AP.Instructions.maybe_mirror_create_note/1` and
  `Federation.NoteFetcher`) store a remote note's MFM (Misskey Flavored
  Markdown) source here, so the source round-trips instead of collapsing
  to rendered HTML.
  """

  def change do
    alter table(:notes) do
      add :mfm, :text
    end
  end
end
