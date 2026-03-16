# SPDX-License-Identifier: MPL-2.0
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
