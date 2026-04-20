# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiDelivery.Schema.Follow do
  use Ecto.Schema

  schema "follows" do
    field :follower_uri, :string
    field :followee_id, :integer
    field :state, :string, default: "pending"

    timestamps(type: :utc_datetime, inserted_at: :created_at, updated_at: false)
  end
end
