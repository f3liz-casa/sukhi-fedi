# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiDelivery.Schema.Relay do
  use Ecto.Schema

  schema "relays" do
    field :actor_uri, :string
    field :inbox_uri, :string
    field :state, :string, default: "pending"

    timestamps(type: :utc_datetime)
  end
end
