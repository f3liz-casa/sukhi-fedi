# SPDX-License-Identifier: MPL-2.0
defmodule SukhiFedi.Schema.Media do
  use Ecto.Schema
  import Ecto.Changeset

  schema "media" do
    field :url, :string
    field :remote_url, :string
    field :type, :string
    field :blurhash, :string
    field :description, :string
    field :width, :integer
    field :height, :integer
    field :size, :integer
    field :tags, {:array, :string}, default: []
    belongs_to :account, SukhiFedi.Schema.Account
    many_to_many :notes, SukhiFedi.Schema.Note, join_through: "note_media"

    timestamps(type: :utc_datetime, inserted_at: :created_at, updated_at: false)
  end

  def changeset(media, attrs) do
    media
    |> cast(attrs, [:url, :remote_url, :type, :blurhash, :description, :width, :height, :size, :tags, :account_id])
    |> validate_required([:url, :type, :account_id])
    |> validate_inclusion(:type, ["image", "video", "audio", "unknown"])
  end
end
