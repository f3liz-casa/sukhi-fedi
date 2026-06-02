# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Repo.Migrations.RemoteNoteIdFromPublished do
  use Ecto.Migration

  @moduledoc """
  Mint a *remote* note's snowflake `id` from its `created_at` (origin
  `published`), not the insert clock.

  `snowflake_id()` (the `notes.id` default) builds `((ms_since_2024) << 16) | seq`
  from `clock_timestamp()`. For a live local post that's right — id-time ==
  published. But a remote note arrives whenever we happen to fetch it: a
  back-filled thread or a re-fetched outbox is inserted *now* though it was
  authored hours or days ago, so it gets a fresh id and jumps to the top of
  an id-ordered timeline while showing an old date.

  A `BEFORE INSERT` trigger fixes every remote-insert path at once (a note
  carries `ap_id` ⇔ it's remote): seed the id from `created_at` instead.
  Local notes (`ap_id IS NULL`) keep the `clock_timestamp()` default. The
  trigger only overrides `id` on INSERT, so `RebuildRemoteNoteIds` — which
  inserts its replacement row with `ap_id` NULL and sets `ap_id` by a later
  UPDATE — is left alone.
  """

  def up do
    # Same epoch (2024-01-01) and `snowflake_seq` as snowflake_id/0, so a
    # trigger-minted id and a rebuild-minted id share one id-space and the
    # low-16-bit counter stays globally unique.
    execute("""
    CREATE OR REPLACE FUNCTION snowflake_id_at(ts timestamptz) RETURNS bigint
    LANGUAGE plpgsql AS $$
    DECLARE
      our_epoch_ms bigint := 1704067200000; -- 2024-01-01T00:00:00Z
      ts_ms bigint;
      seq_id bigint;
    BEGIN
      ts_ms := floor(extract(epoch from ts) * 1000)::bigint;
      seq_id := nextval('snowflake_seq') % 65536; -- 16-bit per-ms counter
      RETURN ((ts_ms - our_epoch_ms) << 16) | seq_id;
    END;
    $$;
    """)

    execute("""
    CREATE OR REPLACE FUNCTION set_remote_note_id() RETURNS trigger
    LANGUAGE plpgsql AS $$
    BEGIN
      IF NEW.ap_id IS NOT NULL THEN
        -- created_at is `timestamp without time zone` holding UTC wall time;
        -- read it back as UTC so the epoch matches snowflake_id/0's.
        NEW.id := snowflake_id_at(NEW.created_at AT TIME ZONE 'UTC');
      END IF;
      RETURN NEW;
    END;
    $$;
    """)

    execute("DROP TRIGGER IF EXISTS notes_remote_id_from_published ON notes")

    execute("""
    CREATE TRIGGER notes_remote_id_from_published
      BEFORE INSERT ON notes
      FOR EACH ROW
      EXECUTE FUNCTION set_remote_note_id();
    """)
  end

  def down do
    execute("DROP TRIGGER IF EXISTS notes_remote_id_from_published ON notes")
    execute("DROP FUNCTION IF EXISTS set_remote_note_id()")
    execute("DROP FUNCTION IF EXISTS snowflake_id_at(timestamptz)")
  end
end
