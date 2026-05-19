# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Repo.Migrations.DropUnusedBioFromAccounts do
  use Ecto.Migration

  @moduledoc """
  `accounts.bio` was added alongside `summary` but nothing reads it —
  Mastodon's `note` wire field maps to `summary` via
  `normalize_credentials_attrs`, and no view ever surfaced `bio`.
  Dropping the column outright; the session goal is to retire legacy
  without back-compat shims.
  """

  def change do
    alter table(:accounts) do
      remove :bio, :text
    end
  end
end
