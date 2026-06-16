# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Repo.Migrations.NotesDomainAndLocalApId do
  use Ecto.Migration

  @moduledoc """
  Disentangle two meanings that `notes.ap_id IS NULL` was carrying at once:
  "no AP id yet" and "this note is local". Overloading them is the root of
  a recurring bug family (see the local-note-apid notes): every site that
  needs a local note's AP id has to remember to *derive* it, and a few
  always forget — the unfederated Delete is the latest.

  Fix: give locality its own column and let every note carry a real ap_id.

    * add `notes.domain` (NULL = local, a host = remote), mirroring
      `accounts.domain`. Locality reads switch to this.
    * backfill `domain` from each note's author account.
    * backfill the canonical ap_id for local notes
      (`https://<domain>/users/<username>/notes/<id>`) so it's stored like
      a remote note's — the unique index already holds it, and these URLs
      are unique per id.

  After this, `ap_id` simply means "the note's AP id" everywhere.
  """

  def up do
    alter table(:notes) do
      add :domain, :string
    end

    create index(:notes, [:domain])

    # locality = the author's. Remote authors carry a host; local authors
    # are NULL, so notes.domain stays NULL (the default) for local notes.
    execute("""
    UPDATE notes SET domain = a.domain
    FROM accounts a
    WHERE a.id = notes.account_id AND a.domain IS NOT NULL
    """)

    # local notes never stored their ap_id; mint the canonical URL now.
    domain = local_domain()

    execute("""
    UPDATE notes
    SET ap_id = 'https://#{domain}/users/' || a.username || '/notes/' || notes.id
    FROM accounts a
    WHERE a.id = notes.account_id AND a.domain IS NULL AND notes.ap_id IS NULL
    """)
  end

  def down do
    # restore the old `ap_id IS NULL ⇔ local` invariant before dropping the
    # column, so a rollback to pre-`domain` code classifies notes correctly.
    execute("""
    UPDATE notes SET ap_id = NULL
    FROM accounts a
    WHERE a.id = notes.account_id AND a.domain IS NULL
    """)

    alter table(:notes) do
      remove :domain
    end
  end

  defp local_domain do
    case Application.get_env(:sukhi_fedi, :domain) do
      d when is_binary(d) and d != "" -> String.replace(d, "'", "")
      _ -> "localhost"
    end
  end
end
