# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Repo.Migrations.CreateAdminAudits do
  use Ecto.Migration

  @moduledoc """
  Append-only audit trail of admin / moderation actions — suspend, instance
  block, report resolve, role change.

  Distinct from the high-volume `outbox` (which is *pruned*, see
  create_outbound_events): this is the durable, tamper-resistant record of
  "who did what, when". Retained indefinitely.

    * No foreign keys — the audit must survive deletion of the target
      account (that's the point of an audit trail).
    * Append-only: UPDATE / DELETE / TRUNCATE are blocked by triggers, so the
      trail can't be rewritten even by the app's own DB role (e.g. via SQL
      injection or a compromised admin). Privileges are revoked too as
      defence-in-depth.
    * Minimal by design — action metadata only, never post content.
  """

  def change do
    create table(:admin_audits) do
      add(:action, :string, null: false)
      add(:admin_account_id, :bigint)
      add(:target_account_id, :bigint)
      add(:target_domain, :string)
      add(:reason, :text)
      add(:metadata, :map, null: false, default: %{})
      timestamps(type: :utc_datetime, inserted_at: :created_at, updated_at: false)
    end

    create(index(:admin_audits, [:created_at]))
    create(index(:admin_audits, [:action]))

    execute(
      """
      CREATE OR REPLACE FUNCTION admin_audits_append_only() RETURNS trigger AS $$
      BEGIN
        RAISE EXCEPTION 'admin_audits is append-only (% blocked)', TG_OP;
      END;
      $$ LANGUAGE plpgsql;
      """,
      "DROP FUNCTION IF EXISTS admin_audits_append_only() CASCADE;"
    )

    execute(
      """
      CREATE TRIGGER admin_audits_no_row_mutation
        BEFORE UPDATE OR DELETE ON admin_audits
        FOR EACH ROW EXECUTE FUNCTION admin_audits_append_only();
      """,
      "DROP TRIGGER IF EXISTS admin_audits_no_row_mutation ON admin_audits;"
    )

    execute(
      """
      CREATE TRIGGER admin_audits_no_truncate
        BEFORE TRUNCATE ON admin_audits
        FOR EACH STATEMENT EXECUTE FUNCTION admin_audits_append_only();
      """,
      "DROP TRIGGER IF EXISTS admin_audits_no_truncate ON admin_audits;"
    )

    # Defence-in-depth: drop the mutation privileges too. The triggers are the
    # hard stop; this also makes the intent explicit at the privilege layer.
    execute(
      "REVOKE UPDATE, DELETE, TRUNCATE ON admin_audits FROM PUBLIC;",
      "GRANT UPDATE, DELETE, TRUNCATE ON admin_audits TO PUBLIC;"
    )
  end
end
