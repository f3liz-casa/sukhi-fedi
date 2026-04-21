# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Schema.OauthAuthorizationCode do
  use Ecto.Schema
  import Ecto.Changeset

  schema "oauth_authorization_codes" do
    field :code_hash, :string
    field :redirect_uri, :string
    field :scopes, :string
    field :expires_at, :utc_datetime
    field :used_at, :utc_datetime
    belongs_to :app, SukhiFedi.Schema.OauthApp
    belongs_to :account, SukhiFedi.Schema.Account

    timestamps(type: :utc_datetime, inserted_at: :created_at, updated_at: false)
  end

  @required [:code_hash, :redirect_uri, :scopes, :expires_at, :app_id, :account_id]
  @optional [:used_at]

  def changeset(code, attrs) do
    code
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> unique_constraint(:code_hash)
  end
end
