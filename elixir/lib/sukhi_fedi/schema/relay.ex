# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Schema.Relay do
  use Ecto.Schema
  import Ecto.Changeset

  schema "relays" do
    field :actor_uri, :string
    field :inbox_uri, :string
    field :state, :string, default: "pending"
    belongs_to :created_by, SukhiFedi.Schema.Account

    timestamps(type: :utc_datetime)
  end

  def changeset(relay, attrs) do
    relay
    |> cast(attrs, [:actor_uri, :inbox_uri, :state, :created_by_id])
    |> validate_required([:actor_uri, :inbox_uri])
    |> validate_inclusion(:state, ["pending", "accepted", "rejected"])
    |> unique_constraint(:actor_uri)
  end
end
