# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiDelivery.Schema.Account do
  @moduledoc """
  Read-only projection of the gateway's `accounts` table. The delivery
  node only needs `username` (for URI → account lookup) and
  `private_key_jwk` (for signing outbound requests via Bun).
  """

  use Ecto.Schema

  schema "accounts" do
    field :username, :string
    field :display_name, :string
    field :summary, :string
    field :public_key_pem, :string
    field :avatar_url, :string
    field :banner_url, :string
    field :private_key_jwk, :map
    # Ed25519 pair (gateway-side migration): the private JWK signs
    # FEP-8b32 Object Integrity Proofs on outbound activities, the
    # precomputed Multikey form goes into actor JSON's `assertionMethod`.
    field :ed25519_private_key_jwk, :map
    field :ed25519_public_multibase, :string
    # Remote-actor mirror columns (gateway-side migration). NULL for
    # locally-hosted accounts; set for upserted remote shadows.
    field :domain, :string
    field :actor_uri, :string
    field :inbox_url, :string
    field :shared_inbox_url, :string
    # Mirrors AP `manuallyApprovesFollowers` / Mastodon `locked`.
    # ActorJson.build_person/1 reads it when fanning out Update(Actor).
    field :locked, :boolean, default: false

    timestamps(type: :utc_datetime, inserted_at: :created_at, updated_at: false)
  end
end
