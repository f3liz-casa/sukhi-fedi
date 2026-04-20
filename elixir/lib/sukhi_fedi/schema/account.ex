# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Schema.Account do
  use Ecto.Schema

  schema "accounts" do
    field :username, :string
    field :display_name, :string
    field :summary, :string
    field :token, :string
    field :private_key_jwk, :map
    field :public_key_jwk, :map
    # PEM-encoded SubjectPublicKeyInfo — read by actor_controller.ex for
    # ActivityPub actor JSON publication.
    field :public_key_pem, :string
    # Auto-created actors for the NodeInfo monitor bot.
    field :is_bot, :boolean, default: false
    field :monitored_domain, :string

    timestamps(type: :utc_datetime, inserted_at: :created_at, updated_at: false)
  end
end
