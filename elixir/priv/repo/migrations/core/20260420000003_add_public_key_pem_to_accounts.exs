# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Repo.Migrations.AddPublicKeyPemToAccounts do
  use Ecto.Migration

  def change do
    alter table(:accounts) do
      # PEM-encoded SubjectPublicKeyInfo for this actor's signing key.
      # ActivityPub actor JSON's `publicKey.publicKeyPem` reads from this.
      add :public_key_pem, :text
      # Bot accounts are auto-created by the NodeInfo monitor; they have no
      # password and shouldn't show up in human account listings.
      add :is_bot, :boolean, null: false, default: false
      # For monitor bots: the remote domain this actor reports on.
      add :monitored_domain, :string
    end

    create index(:accounts, [:is_bot])
    create unique_index(:accounts, [:monitored_domain], where: "monitored_domain IS NOT NULL")
  end
end
