# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Repo.Migrations.CreateInviteCodes do
  use Ecto.Migration

  @moduledoc """
  Invite codes for the closed-registration signup flow. Admins issue a
  code from the admin UI, hand it to the prospective user, and `POST
  /api/v1/accounts` consumes it. One code, one account; the consumer
  link is left in place after use so an admin can see who joined with
  which invite.
  """

  def change do
    create table(:invite_codes) do
      add :code, :string, null: false
      add :issued_by_id, references(:accounts, on_delete: :nilify_all)
      add :consumed_by_id, references(:accounts, on_delete: :nilify_all)
      add :consumed_at, :utc_datetime
      add :expires_at, :utc_datetime
      add :note, :string

      timestamps(type: :utc_datetime, inserted_at: :created_at, updated_at: false)
    end

    create unique_index(:invite_codes, [:code])
    create index(:invite_codes, [:consumed_by_id])
  end
end
