# SPDX-License-Identifier: MPL-2.0
defmodule SukhiFedi.Schema.PinnedNote do
  use Ecto.Schema
  import Ecto.Changeset

  schema "pinned_notes" do
    belongs_to :account, SukhiFedi.Schema.Account
    belongs_to :note, SukhiFedi.Schema.Note
    field :position, :integer, default: 0
    field :created_at, :utc_datetime, autogenerate: {DateTime, :utc_now, []}
  end

  def changeset(pinned_note, attrs) do
    pinned_note
    |> cast(attrs, [:account_id, :note_id, :position])
    |> validate_required([:account_id, :note_id])
    |> unique_constraint([:account_id, :note_id])
  end
end
