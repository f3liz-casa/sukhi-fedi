# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Repo.Migrations.AddSensitiveToNotes do
  use Ecto.Migration

  @moduledoc """
  The AP `sensitive` flag (Mastodon/Misskey NSFW marker) was never stored —
  the Mastodon view derived `sensitive` from the presence of a content
  warning, so a post flagged sensitive *without* a CW looked safe. Keep the
  real flag so the SPA can blur NSFW media on its own.
  """

  def change do
    alter table(:notes) do
      add(:sensitive, :boolean, null: false, default: false)
    end
  end
end
