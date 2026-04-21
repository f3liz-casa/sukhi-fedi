# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Repo.Migrations.AddHotPathIndexes do
  use Ecto.Migration

  def up do
    # Public timeline: `WHERE visibility = 'public' ORDER BY created_at DESC`
    create index(:notes, [:visibility, :created_at])

    # FEP-8fcf digest + "who follows X" queries all filter by state='accepted'.
    # A plain (follower_uri, followee_id) unique already exists but doesn't
    # cover state-filtered reads.
    create_if_not_exists index(:follows, [:followee_id, :state])
    create_if_not_exists index(:follows, [:follower_uri, :state])

    # Outbox.Relay only ever reads rows where status='pending'. Replacing the
    # full (status, id) index with a partial index keeps it tiny once the
    # table is dominated by published rows.
    drop_if_exists index(:outbox, [:status, :id])
    create index(:outbox, [:id], where: "status = 'pending'", name: :outbox_pending_id_index)

    # Swap per-row NOTIFY trigger for a per-statement one. Relay re-queries
    # on wake-up, so payload is unused — firing once per INSERT statement is
    # sufficient and avoids amplification on bulk inserts.
    execute "DROP TRIGGER IF EXISTS outbox_insert_notify ON outbox;"

    execute """
    CREATE OR REPLACE FUNCTION outbox_notify() RETURNS trigger AS $$
    BEGIN
      PERFORM pg_notify('outbox_new', '');
      RETURN NULL;
    END;
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE TRIGGER outbox_insert_notify
    AFTER INSERT ON outbox
    FOR EACH STATEMENT EXECUTE FUNCTION outbox_notify();
    """
  end

  def down do
    execute "DROP TRIGGER IF EXISTS outbox_insert_notify ON outbox;"

    execute """
    CREATE OR REPLACE FUNCTION outbox_notify() RETURNS trigger AS $$
    BEGIN
      PERFORM pg_notify('outbox_new', NEW.id::text);
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE TRIGGER outbox_insert_notify
    AFTER INSERT ON outbox
    FOR EACH ROW EXECUTE FUNCTION outbox_notify();
    """

    drop_if_exists index(:outbox, [:id], name: :outbox_pending_id_index)
    create index(:outbox, [:status, :id])

    drop_if_exists index(:follows, [:follower_uri, :state])
    drop_if_exists index(:follows, [:followee_id, :state])
    drop_if_exists index(:notes, [:visibility, :created_at])
  end
end
