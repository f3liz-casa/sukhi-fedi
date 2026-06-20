# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Repo.Migrations.InviteCodesMultiUseAndProxy do
  use Ecto.Migration

  @moduledoc """
  Grow invite codes from single-use to multi-use, and let an admin issue
  one *on behalf of* another local account (delegated / proxy issuance).

    * `max_uses` (>= 1) + `uses_count` replace the single `consumed_at`
      flag: a code is live while `uses_count < max_uses`. Default 1, so an
      ordinary code stays single-use. Each joiner moves to its own
      `invite_code_uses` row, so a multi-use code can still show everyone
      who joined with it.
    * `on_behalf_of_id` is the account the code is *attributed* to — the
      `/invite/:code` greeting reads "@that_user invited you" — while
      `issued_by_id` stays the admin who actually minted it (audit).

  The old `consumed_at` / `consumed_by_id` are folded into the new shape
  and dropped, so "is this code still good?" has a single source of truth.
  """

  def up do
    create table(:invite_code_uses) do
      add :invite_code_id, references(:invite_codes, on_delete: :delete_all), null: false
      add :account_id, references(:accounts, on_delete: :nilify_all)
      add :used_at, :utc_datetime, null: false
    end

    create index(:invite_code_uses, [:invite_code_id])
    # An account signs up once, so it claims at most one code ever — the
    # guard is belt-and-suspenders against a double-count on one code.
    create unique_index(:invite_code_uses, [:invite_code_id, :account_id])

    alter table(:invite_codes) do
      add :on_behalf_of_id, references(:accounts, on_delete: :nilify_all)
      add :max_uses, :integer, null: false, default: 1
      add :uses_count, :integer, null: false, default: 0
    end

    # Carry every already-consumed code into the new shape: one use row,
    # uses_count = 1 (max_uses defaults to 1, so they stay single-use).
    execute """
    INSERT INTO invite_code_uses (invite_code_id, account_id, used_at)
    SELECT id, consumed_by_id, consumed_at
    FROM invite_codes
    WHERE consumed_at IS NOT NULL
    """

    execute "UPDATE invite_codes SET uses_count = 1 WHERE consumed_at IS NOT NULL"

    alter table(:invite_codes) do
      remove :consumed_at
      remove :consumed_by_id
    end
  end

  def down do
    alter table(:invite_codes) do
      add :consumed_at, :utc_datetime
      add :consumed_by_id, references(:accounts, on_delete: :nilify_all)
    end

    # Best-effort reverse: fold the earliest joiner back into the
    # single-use columns. Any multi-use history beyond the first is lost.
    execute """
    UPDATE invite_codes ic
    SET consumed_at = u.used_at, consumed_by_id = u.account_id
    FROM (
      SELECT DISTINCT ON (invite_code_id) invite_code_id, account_id, used_at
      FROM invite_code_uses
      ORDER BY invite_code_id, used_at ASC
    ) u
    WHERE u.invite_code_id = ic.id
    """

    create index(:invite_codes, [:consumed_by_id])

    alter table(:invite_codes) do
      remove :on_behalf_of_id
      remove :max_uses
      remove :uses_count
    end

    drop table(:invite_code_uses)
  end
end
