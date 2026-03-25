# SPDX-License-Identifier: MPL-2.0
defmodule SukhiFedi.Schema.Note do
  use Ecto.Schema
  import Ecto.Changeset

  schema "notes" do
    field :content, :string
    field :visibility, :string, default: "public"
    field :ap_id, :string
    field :cw, :string
    field :mfm, :string
    belongs_to :account, SukhiFedi.Schema.Account
    many_to_many :media, SukhiFedi.Schema.Media, join_through: "note_media"
    has_one :poll, SukhiFedi.Schema.Poll
    has_many :reactions, SukhiFedi.Schema.Reaction

    timestamps(type: :utc_datetime, inserted_at: :created_at, updated_at: false)
  end

  def changeset(note, attrs) do
    note
    |> cast(attrs, [:content, :visibility, :account_id, :cw, :mfm])
    |> validate_required([:content, :account_id])
    |> validate_inclusion(:visibility, ["public", "followers"])
  end
end
