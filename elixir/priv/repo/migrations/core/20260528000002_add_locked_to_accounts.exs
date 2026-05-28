# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Repo.Migrations.AddLockedToAccounts do
  use Ecto.Migration

  @moduledoc """
  Adds `locked` to `accounts`. Maps to ActivityPub
  `manuallyApprovesFollowers` on the wire and to Mastodon API `locked`
  on the client. For local rows it's whether the user requires manual
  approval of follow requests; for remote rows it mirrors the value
  parsed from the remote actor JSON.

  NOT NULL DEFAULT false because Mastodon clients treat `locked` as a
  required boolean; a null would have to be coerced to false on read
  anyway.
  """

  def change do
    alter table(:accounts) do
      add :locked, :boolean, null: false, default: false
    end
  end
end
