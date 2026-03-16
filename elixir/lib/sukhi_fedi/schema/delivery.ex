# SPDX-License-Identifier: MPL-2.0
defmodule SukhiFedi.Schema.Delivery do
  use Ecto.Schema

  schema "deliveries" do
    field :object_id, :integer
    field :inbox_url, :string
    field :state, :string, default: "queued"
    field :attempts, :integer, default: 0
    field :next_retry, :utc_datetime

    timestamps(type: :utc_datetime, inserted_at: :created_at, updated_at: false)
  end
end
