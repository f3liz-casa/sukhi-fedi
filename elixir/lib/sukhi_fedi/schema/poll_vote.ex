# SPDX-License-Identifier: MPL-2.0
defmodule SukhiFedi.Schema.PollVote do
  use Ecto.Schema
  import Ecto.Changeset

  schema "poll_votes" do
    belongs_to :account, SukhiFedi.Schema.Account
    belongs_to :poll, SukhiFedi.Schema.Poll
    belongs_to :option, SukhiFedi.Schema.PollOption

    timestamps(type: :utc_datetime, inserted_at: :created_at, updated_at: false)
  end

  def changeset(vote, attrs) do
    vote
    |> cast(attrs, [:account_id, :poll_id, :option_id])
    |> validate_required([:account_id, :poll_id, :option_id])
    |> unique_constraint([:account_id, :poll_id, :option_id])
  end
end
