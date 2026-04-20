# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Repo.Migrations.CreateOutbox do
  use Ecto.Migration

  def up do
    create table(:outbox) do
      add :aggregate_type, :string, null: false
      add :aggregate_id, :string, null: false
      add :subject, :string, null: false
      add :payload, :map, null: false
      add :headers, :map, null: false, default: %{}
      add :status, :string, null: false, default: "pending"
      add :attempts, :integer, null: false, default: 0
      add :last_error, :text
      add :inserted_at, :utc_datetime_usec, null: false, default: fragment("now()")
      add :published_at, :utc_datetime_usec
    end

    create index(:outbox, [:status, :id])
    create index(:outbox, [:aggregate_type, :aggregate_id])

    # Notify Outbox.Relay when a new row arrives so it can wake up
    # without waiting for the periodic poll interval.
    execute """
    CREATE FUNCTION outbox_notify() RETURNS trigger AS $$
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
  end

  def down do
    execute "DROP TRIGGER IF EXISTS outbox_insert_notify ON outbox;"
    execute "DROP FUNCTION IF EXISTS outbox_notify();"
    drop table(:outbox)
  end
end
