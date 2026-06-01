# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Repo.Migrations.AddOriginIndexes do
  use Ecto.Migration

  @moduledoc """
  A partial index over the remote-origin accounts, so the "wipe & rebuild
  remote" maintenance path (and any remote-only scan) doesn't sequential-scan
  the table. Origin is `domain IS NULL` for accounts — this indexes the
  NOT NULL (remote) side, mirroring the existing
  `accounts_monitored_domain` partial index. See
  `SukhiFedi.Accounts.remote_accounts/1`.

  Notes need no companion index: `notes.ap_id` already carries a unique
  index (`create_notes` migration), which Postgres uses for the
  `ap_id IS NOT NULL` (remote) scan that `SukhiFedi.Notes.remote_notes/1`
  builds — adding a partial one would be redundant.
  """

  def change do
    create index(:accounts, [:domain],
             where: "domain IS NOT NULL",
             name: :accounts_remote_domain_index
           )
  end
end
