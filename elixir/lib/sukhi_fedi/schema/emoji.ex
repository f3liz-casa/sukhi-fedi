# SPDX-License-Identifier: MPL-2.0
defmodule SukhiFedi.Schema.Emoji do
  use Ecto.Schema
  import Ecto.Changeset

  schema "emojis" do
    field :shortcode, :string
    field :url, :string
    field :category, :string
    field :aliases, {:array, :string}, default: []

    timestamps(type: :utc_datetime, inserted_at: :created_at, updated_at: false)
  end

  def changeset(emoji, attrs) do
    emoji
    |> cast(attrs, [:shortcode, :url, :category, :aliases])
    |> validate_required([:shortcode, :url])
    |> unique_constraint(:shortcode)
  end
end
