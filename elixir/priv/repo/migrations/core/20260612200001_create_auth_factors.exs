# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Repo.Migrations.CreateAuthFactors do
  use Ecto.Migration

  @moduledoc """
  Auth factors beyond the password: verified email (login codes), TOTP
  (authenticator-app 2FA), and WebAuthn passkeys.

  - `accounts.email` becomes meaningful: `email_verified_at` marks an
    address that completed the code round-trip. The partial unique
    index delivers the uniqueness `20260527000001` deferred ("once the
    field is mandatory" — that is now), but only over *verified*
    addresses: an unverified signup entry must not be able to squat
    someone else's mailbox, so whoever completes the code round-trip
    first owns the address. Legacy rows are all unverified, so the
    index build cannot collide with existing data.
  - `email_codes` holds the short-lived 6-digit codes for both
    verification and email login. Only the SHA-256 hash of a code is
    stored (same rule as sessions / oauth tokens).
  - `webauthn_credentials` are registered passkeys; `cose_key` is the
    COSE public key map in external term format.
  - `webauthn_challenges` parks the in-flight Wax challenge between the
    options request and the browser's response, keyed by a random ref.
  """

  def up do
    alter table(:accounts) do
      add :email_verified_at, :utc_datetime
      add :totp_secret, :binary
      add :totp_enabled_at, :utc_datetime
      add :totp_last_used_step, :bigint
    end

    execute """
    CREATE UNIQUE INDEX accounts_local_email_index
    ON accounts (lower(email))
    WHERE domain IS NULL AND email IS NOT NULL AND email_verified_at IS NOT NULL
    """

    create table(:email_codes) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :email, :string, null: false
      add :purpose, :string, null: false
      add :code_hash, :string, null: false
      add :attempts, :integer, null: false, default: 0
      add :expires_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime, inserted_at: :created_at, updated_at: false)
    end

    # One live code per (account, purpose): a new request replaces it.
    create unique_index(:email_codes, [:account_id, :purpose])

    create table(:webauthn_credentials) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :credential_id, :string, null: false
      add :cose_key, :binary, null: false
      add :sign_count, :bigint, null: false, default: 0
      add :nickname, :string
      add :last_used_at, :utc_datetime

      timestamps(type: :utc_datetime, inserted_at: :created_at, updated_at: false)
    end

    create unique_index(:webauthn_credentials, [:credential_id])
    create index(:webauthn_credentials, [:account_id])

    create table(:webauthn_challenges) do
      add :ref, :string, null: false
      # NULL for login challenges — nobody is signed in yet.
      add :account_id, references(:accounts, on_delete: :delete_all)
      add :purpose, :string, null: false
      add :challenge, :binary, null: false
      add :expires_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime, inserted_at: :created_at, updated_at: false)
    end

    create unique_index(:webauthn_challenges, [:ref])
  end

  def down do
    drop table(:webauthn_challenges)
    drop table(:webauthn_credentials)
    drop table(:email_codes)

    execute "DROP INDEX accounts_local_email_index"

    alter table(:accounts) do
      remove :email_verified_at
      remove :totp_secret
      remove :totp_enabled_at
      remove :totp_last_used_step
    end
  end
end
