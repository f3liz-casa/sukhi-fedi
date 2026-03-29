# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Schema.Session do
  use Ecto.Schema

  schema "sessions" do
    field :token_hash, :string
    field :expires_at, :utc_datetime
    belongs_to :account, SukhiFedi.Schema.Account

    timestamps(type: :utc_datetime, inserted_at: :created_at, updated_at: false)
  end
end
