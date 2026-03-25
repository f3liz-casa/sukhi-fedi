# SPDX-License-Identifier: MPL-2.0
defmodule SukhiFedi.Schema.OauthConnection do
  use Ecto.Schema

  schema "oauth_connections" do
    field :provider, :string
    field :provider_uid, :string
    belongs_to :account, SukhiFedi.Schema.Account

    timestamps(type: :utc_datetime, inserted_at: :created_at, updated_at: false)
  end
end
