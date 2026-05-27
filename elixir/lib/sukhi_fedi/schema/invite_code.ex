# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Schema.InviteCode do
  use Ecto.Schema

  schema "invite_codes" do
    field :code, :string
    field :consumed_at, :utc_datetime
    field :expires_at, :utc_datetime
    field :note, :string

    belongs_to :issued_by, SukhiFedi.Schema.Account, foreign_key: :issued_by_id
    belongs_to :consumed_by, SukhiFedi.Schema.Account, foreign_key: :consumed_by_id

    timestamps(type: :utc_datetime, inserted_at: :created_at, updated_at: false)
  end
end
