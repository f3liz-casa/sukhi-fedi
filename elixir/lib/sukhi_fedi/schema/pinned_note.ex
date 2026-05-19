# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Schema.PinnedNote do
  use Ecto.Schema
  import Ecto.Changeset

  schema "pinned_notes" do
    belongs_to :account, SukhiFedi.Schema.Account
    belongs_to :note, SukhiFedi.Schema.Note
    field :position, :integer, default: 0

    timestamps(type: :utc_datetime, inserted_at: :created_at, updated_at: false)
  end

  def changeset(pinned_note, attrs) do
    pinned_note
    |> cast(attrs, [:account_id, :note_id, :position])
    |> validate_required([:account_id, :note_id])
    |> unique_constraint([:account_id, :note_id])
  end
end
