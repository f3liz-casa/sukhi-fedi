# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Repo.Migrations.EmailCodesForSignup do
  use Ecto.Migration

  @moduledoc """
  Signup now proves the mailbox *before* the account exists (so a
  passwordless account is born able to log in). Pre-account codes have
  no `account_id` — make it nullable and give the orphan rows their
  own one-live-code rule keyed by address.
  """

  def up do
    execute "ALTER TABLE email_codes ALTER COLUMN account_id DROP NOT NULL"

    execute """
    CREATE UNIQUE INDEX email_codes_signup_index
    ON email_codes (lower(email), purpose) WHERE account_id IS NULL
    """
  end

  def down do
    execute "DROP INDEX email_codes_signup_index"
    execute "DELETE FROM email_codes WHERE account_id IS NULL"
    execute "ALTER TABLE email_codes ALTER COLUMN account_id SET NOT NULL"
  end
end
