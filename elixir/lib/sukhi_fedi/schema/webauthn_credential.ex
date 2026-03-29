# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Schema.WebauthnCredential do
  use Ecto.Schema

  schema "webauthn_credentials" do
    field :credential_id, :binary
    field :public_key, :binary
    field :sign_count, :integer
    belongs_to :account, SukhiFedi.Schema.Account

    timestamps(type: :utc_datetime, inserted_at: :created_at, updated_at: false)
  end
end
