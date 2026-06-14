# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Repo.Migrations.AddTitleToNotes do
  use Ecto.Migration

  @moduledoc """
  An inbound `Article` (hackers.pub long-form post) carries a human
  title in AP `name` that a plain `Note` never has. We keep it as a
  structured column — separate from the `<h2>` we fold into `content`
  for Mastodon-client compatibility — so our own client can detect an
  article, route it to its reader page, and use the bare title as the
  page `<title>`. NULL for every non-article note.
  """

  def change do
    alter table(:notes) do
      add :title, :text
    end
  end
end
