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
    field :private_key_jwk, :map

    timestamps(type: :utc_datetime, inserted_at: :created_at, updated_at: false)
  end
end
