# SPDX-License-Identifier: MPL-2.0
defmodule SukhiFedi.Schema.Reaction do
  use Ecto.Schema
  import Ecto.Changeset

  schema "reactions" do
    field :emoji, :string
    field :ap_id, :string
    belongs_to :account, SukhiFedi.Schema.Account
    belongs_to :note, SukhiFedi.Schema.Note

    timestamps(type: :utc_datetime, inserted_at: :created_at, updated_at: false)
  end

  def changeset(reaction, attrs) do
    reaction
    |> cast(attrs, [:emoji, :ap_id, :account_id, :note_id])
    |> validate_required([:emoji, :account_id, :note_id])
    |> unique_constraint([:account_id, :note_id, :emoji])
  end
end
