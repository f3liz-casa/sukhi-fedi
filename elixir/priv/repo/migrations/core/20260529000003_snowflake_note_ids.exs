# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Repo.Migrations.SnowflakeNoteIds do
  use Ecto.Migration

  @moduledoc """
  Stop minting sequential `notes.id`. New notes get a Snowflake-style id
  instead: `((ms_since_2024) << 16) | counter`. It stays a `bigint` (FKs
  and the PK type are untouched) and is time-sortable, so id-based
  pagination keeps working — but it's not enumerable and the max id no
  longer leaks the post count.

  The id is the public identity (it forms the AP id
  `…/users/<u>/notes/<id>` and the Mastodon API `id`), and a federated
  AP id is immutable, so this only changes **new** notes; existing rows
  keep their small sequential ids. New Snowflake ids are ~10^15, far
  above any existing sequential id, so the two coexist without collision
  and old notes still sort oldest.

  The Mastodon API serialises `id` as a string (Id.encode), so Snowflake
  values exceeding JS's 2^53 never lose precision client-side.
  """

  def up do
    execute("CREATE SEQUENCE IF NOT EXISTS snowflake_seq")

    execute("""
    CREATE OR REPLACE FUNCTION snowflake_id() RETURNS bigint
    LANGUAGE plpgsql AS $$
    DECLARE
      our_epoch_ms bigint := 1704067200000; -- 2024-01-01T00:00:00Z
      now_ms bigint;
      seq_id bigint;
    BEGIN
      now_ms := floor(extract(epoch from clock_timestamp()) * 1000)::bigint;
      seq_id := nextval('snowflake_seq') % 65536; -- 16-bit per-ms counter
      RETURN ((now_ms - our_epoch_ms) << 16) | seq_id;
    END;
    $$;
    """)

    execute("ALTER TABLE notes ALTER COLUMN id SET DEFAULT snowflake_id()")
  end

  def down do
    execute("ALTER TABLE notes ALTER COLUMN id SET DEFAULT nextval('notes_id_seq'::regclass)")
    execute("DROP FUNCTION IF EXISTS snowflake_id()")
    execute("DROP SEQUENCE IF EXISTS snowflake_seq")
  end
end
