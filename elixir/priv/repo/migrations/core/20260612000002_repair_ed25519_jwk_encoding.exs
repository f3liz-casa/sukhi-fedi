# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Repo.Migrations.RepairEd25519JwkEncoding do
  use Ecto.Migration

  @moduledoc """
  The 20260612000001 backfill handed `$1::jsonb` an already-encoded
  JSON string; the prepared statement infers the parameter's type as
  jsonb, so postgrex's jsonb encoder wrapped that text once more and
  the column ended up holding a jsonb *string*. Ecto cannot load that
  as `:map`, so every load of a backfilled local account raised —
  token verification and actor documents 500'd for existing users.

  Unwrap the string back into the object it contains. Rows written
  correctly (the runtime KeyGen path, or 000001 as fixed alongside
  this migration) are jsonb objects and are untouched — re-running
  is a no-op. The key material itself was always intact.
  """

  def up do
    execute("""
    UPDATE accounts
    SET ed25519_private_key_jwk = (ed25519_private_key_jwk #>> '{}')::jsonb
    WHERE ed25519_private_key_jwk IS NOT NULL
      AND jsonb_typeof(ed25519_private_key_jwk) = 'string'
    """)
  end

  def down, do: :ok
end
