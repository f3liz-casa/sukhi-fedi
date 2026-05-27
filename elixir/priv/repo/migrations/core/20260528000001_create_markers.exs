# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Repo.Migrations.CreateMarkers do
  use Ecto.Migration

  @moduledoc """
  Per-account read-position markers backing `/api/v1/markers`.

  Mastodon clients (Moshidon, Ivory, ...) sync their last-seen
  position on home + notifications across devices through this
  endpoint. One row per (account, timeline); `version` bumps on each
  POST so clients can detect conflicts.
  """

  def change do
    create table(:markers) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :timeline, :string, null: false
      add :last_read_id, :string, null: false
      add :version, :integer, null: false, default: 1
      timestamps()
    end

    create unique_index(:markers, [:account_id, :timeline])
  end
end
