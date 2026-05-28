# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiDelivery.Schema.CustomEmoji do
  @moduledoc """
  Read-only projection of the gateway's `custom_emojis` table. The
  delivery node looks up icon URLs for local emoji shortcodes so it
  can attach a `tag` Emoji entry when fanning out an emoji reaction.
  """

  use Ecto.Schema

  schema "custom_emojis" do
    field :shortcode, :string
    field :domain, :string
    field :image_url, :string
    field :static_url, :string
    timestamps(type: :utc_datetime, inserted_at: :created_at, updated_at: false)
  end
end
