# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Schema.Poll do
  use Ecto.Schema
  import Ecto.Changeset

  schema "polls" do
    field :expires_at, :utc_datetime
    field :multiple, :boolean, default: false
    belongs_to :note, SukhiFedi.Schema.Note
    has_many :options, SukhiFedi.Schema.PollOption
    has_many :votes, SukhiFedi.Schema.PollVote

    timestamps(type: :utc_datetime, inserted_at: :created_at, updated_at: false)
  end

  def changeset(poll, attrs) do
    poll
    |> cast(attrs, [:expires_at, :multiple, :note_id])
    |> validate_required([:note_id])
  end
end
