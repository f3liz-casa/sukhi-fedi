# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Schema.Object do
  use Ecto.Schema

  schema "objects" do
    field :ap_id, :string
    field :type, :string
    field :actor_id, :string
    field :raw_json, :map

    timestamps(type: :utc_datetime, inserted_at: :created_at, updated_at: false)
  end
end
