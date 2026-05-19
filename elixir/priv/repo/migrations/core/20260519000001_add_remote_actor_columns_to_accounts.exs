# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Repo.Migrations.AddRemoteActorColumnsToAccounts do
  use Ecto.Migration

  @moduledoc """
  Add the columns that turn `accounts` from a local-only table into a
  unified directory containing both local users and upserted remote
  shadow actors.

  Strategy: a row is local iff `domain IS NULL`. For local rows
  `actor_uri` is derived (host + username), so we don't store it.
  For remote rows `actor_uri` is the canonical AP id and uniquely
  identifies the row.

  Uniqueness:
    * Local: at most one row per `username` where `domain IS NULL`
      (partial unique index — preserves the existing constraint).
    * Remote: at most one row per `actor_uri` where it is set.
  """

  def change do
    alter table(:accounts) do
      add :domain, :text
      add :actor_uri, :text
      add :inbox_url, :text
      add :shared_inbox_url, :text
      add :public_key_id, :text
      add :last_fetched_at, :utc_datetime
    end

    # Drop the old bare unique on username and replace with partial
    # uniques. Both rows of a (username, domain) pair coexist this way:
    # a local `alice` does not collide with remote `alice@social.example`.
    drop unique_index(:accounts, [:username])

    create unique_index(:accounts, [:username],
             where: "domain IS NULL",
             name: :accounts_local_username_index
           )

    create unique_index(:accounts, [:actor_uri],
             where: "actor_uri IS NOT NULL",
             name: :accounts_actor_uri_index
           )

    # Fast lookup by (username, domain) when resolving remote acct: handles.
    create index(:accounts, [:username, :domain])
  end
end
