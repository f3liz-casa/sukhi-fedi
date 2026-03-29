# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Schema.Article do
  use Ecto.Schema

  schema "articles" do
    belongs_to :account, SukhiFedi.Schema.Account
    field :ap_id, :string
    field :title, :string
    field :content, :string
    field :summary, :string
    field :published_at, :utc_datetime
    field :updated_at_ap, :utc_datetime
    timestamps()
  end
end
