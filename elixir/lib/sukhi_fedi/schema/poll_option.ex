# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Schema.PollOption do
  use Ecto.Schema
  import Ecto.Changeset

  schema "poll_options" do
    field :title, :string
    field :position, :integer
    belongs_to :poll, SukhiFedi.Schema.Poll
    has_many :votes, SukhiFedi.Schema.PollVote
  end

  def changeset(option, attrs) do
    option
    |> cast(attrs, [:title, :position, :poll_id])
    |> validate_required([:title, :position, :poll_id])
  end
end
