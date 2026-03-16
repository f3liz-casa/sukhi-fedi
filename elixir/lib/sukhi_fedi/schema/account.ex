# SPDX-License-Identifier: MPL-2.0
defmodule SukhiFedi.Schema.Account do
  use Ecto.Schema

  schema "accounts" do
    field :username, :string
    field :display_name, :string
    field :summary, :string

    timestamps(type: :utc_datetime, inserted_at: :created_at, updated_at: false)
  end
end
